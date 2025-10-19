// cpp/toydb.cpp

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

using namespace std;
using clk = chrono::steady_clock;

struct Row {
    int y, m, d, h;
    int passenger_count;
    double trip_distance;
    int pulocationid;
    double total_amount;
    double tip_amount;
    double improvement_surcharge;
};

static inline string trim(const string& s) {
    size_t a = 0, b = s.size();
    while (a < b &&
           (s[a] == ' ' || s[a] == '\r' || s[a] == '\n' || s[a] == '\t'))
        a++;
    while (b > a && (s[b - 1] == ' ' || s[b - 1] == '\r' || s[b - 1] == '\n' ||
                     s[b - 1] == '\t'))
        b--;
    return s.substr(a, b - a);
}

static inline int to_int(const string& s) {
    try {
        return s.empty() ? 0 : stoi(s);
    } catch (...) {
        return 0;
    }
}

static inline double to_dbl(const string& s) {
    try {
        return s.empty() ? 0.0 : stod(s);
    } catch (...) {
        return 0.0;
    }
}

// split by comma to resolve csv
static vector<string> split_csv(const string& line) {
    vector<string> out;
    out.reserve(32);
    string cur;
    cur.reserve(64);
    bool in_quotes = false;
    for (size_t i = 0; i < line.size(); ++i) {
        char c = line[i];
        if (c == '"') {
            in_quotes = !in_quotes;
            continue;
        }
        if (c == ',' && !in_quotes) {
            out.push_back(cur);
            cur.clear();
        } else {
            cur.push_back(c);
        }
    }
    out.push_back(cur);
    return out;
}

// detect empty rows
static inline bool is_blank_line(const string& line) {
    for (char c : line) {
        if (!(c == ' ' || c == '\t' || c == '\r' || c == '\n')) return false;
    }
    return true;
}

// NYC 2019 schema indices
enum ColIdx {
    COL_PICKUP = 1,
    COL_PASSENGER = 3,
    COL_TRIPDIST = 4,
    COL_PULOC = 7,
    COL_TIP = 13,
    COL_IMPR = 15,
    COL_TOTAL = 16
};

static bool parse_row(const string& line, Row& r) {
    if (is_blank_line(line)) return false;
    auto cols = split_csv(line);

    constexpr size_t EXPECTED = 19;
    if (cols.size() < EXPECTED) cols.resize(EXPECTED);

    const string& dt = cols[COL_PICKUP];
    if (dt.size() < 13) return false;

    r.y = to_int(dt.substr(0, 4));
    r.m = to_int(dt.substr(5, 2));
    r.d = to_int(dt.substr(8, 2));
    r.h = to_int(dt.substr(11, 2));

    r.passenger_count = to_int(cols[COL_PASSENGER]);
    r.trip_distance = to_dbl(cols[COL_TRIPDIST]);
    r.pulocationid = to_int(cols[COL_PULOC]);
    r.tip_amount = to_dbl(cols[COL_TIP]);
    r.improvement_surcharge = to_dbl(cols[COL_IMPR]);
    r.total_amount = to_dbl(cols[COL_TOTAL]);

    return true;
}

static vector<Row> load_csv(const string& path, size_t limit_rows = 0) {
    vector<Row> rows;
    rows.reserve(1000000);
    ifstream in(path);
    if (!in) {
        cerr << "ERR: cannot open " << path << "\n";
        return rows;
    }
    string line;
    // skip header
    if (!getline(in, line)) return rows;
    size_t n = 0;
    while (getline(in, line)) {
        Row r{};
        if (parse_row(line, r)) {
            rows.push_back(r);
            n++;
            if (limit_rows > 0 && n >= limit_rows) break;
        }
    }
    return rows;
}

struct BenchOut {
    // counts
    long long dataset_rows = 0;
    // q times
    double q1_ms = 0, q2_ms = 0, q3_ms = 0;
    // u1
    long long u1_target = 0, u1_update_rows = 0;
    double u1_ms = 0;
    // u2
    long long u2_target = 0, u2_update_rows = 0;
    double u2_ms = 0;
    // u3
    long long u3_ctas_rows = 0, u3_update_rows = 0;
    double u3_ctas_ms = 0, u3_update_ms = 0, u3_total_ms = 0;
};

static bool in_july_2019(const Row& r) { return r.y == 2019 && r.m == 7; }
static bool on_2019_07_10(const Row& r) {
    return r.y == 2019 && r.m == 7 && r.d == 10;
}

struct TxView {
    const std::vector<Row>& base;
    std::unordered_map<size_t, Row> delta;

    explicit TxView(const std::vector<Row>& b) : base(b) { delta.reserve(1024); }

    inline const Row& get(size_t i) const {
        auto it = delta.find(i);
        if (it != delta.end()) return it->second;
        return base[i];
    }

    template<class Pred, class Apply>
    size_t update(Pred p, Apply a) {
        size_t n=0;
        for (size_t i=0;i<base.size();++i){
            const Row& cur = get(i);
            if (p(cur)) {
                Row copy = cur; a(copy);
                delta[i] = std::move(copy);
                ++n;
            }
        }
        return n;
    }

    void rollback(){ delta.clear(); }
};


// Q1: hourly agg over July 2019, passenger_count>=2  -> measure time, return
// #groups (unused)
static double q1_hourly(const vector<Row>& rows, size_t& groups) {
    auto t0 = clk::now();
    unordered_map<long long, int> cnt;
    cnt.reserve(10000);
    for (const auto& r : rows) {
        if (r.passenger_count >= 2 && in_july_2019(r)) {
            long long key =
                (long long)r.y * 1000000 + r.m * 10000 + r.d * 100 + r.h;
            cnt[key]++;
        }
    }
    groups = cnt.size();
    auto t1 = clk::now();
    return chrono::duration<double, milli>(t1 - t0).count();
}

// Q2: global sort by trip_distance desc, take top-100  -> measure time
static double q2_top100(const vector<Row>& rows) {
    auto t0 = clk::now();
    vector<double> dist;
    dist.reserve(rows.size());
    for (const auto& r : rows) dist.push_back(r.trip_distance);
    const size_t k = 100;
    if (dist.size() > k) {
        nth_element(dist.begin(), dist.begin() + k, dist.end(),
                    greater<double>());
        partial_sort(dist.begin(), dist.begin() + k, dist.end(),
                     greater<double>());
        dist.resize(k);
    } else {
        sort(dist.begin(), dist.end(), greater<double>());
    }
    auto t1 = clk::now();
    return chrono::duration<double, milli>(t1 - t0).count();
}

// Q3: filter 1.0<=distance<=3.0, group by PULocationID, top-20 by count  ->
// measure time
static double q3_locagg(const vector<Row>& rows, size_t& top) {
    auto t0 = clk::now();
    unordered_map<int, long long> cnt;
    cnt.reserve(2000);
    for (const auto& r : rows) {
        if (r.trip_distance >= 1.0 && r.trip_distance <= 3.0) {
            cnt[r.pulocationid]++;
        }
    }
    vector<pair<int, long long>> v;
    v.reserve(cnt.size());
    for (auto& kv : cnt) v.emplace_back(kv.first, kv.second);
    sort(v.begin(), v.end(),
         [](auto& a, auto& b) { return a.second > b.second; });
    if (v.size() > 20) v.resize(20);
    top = v.size();
    auto t1 = clk::now();
    return chrono::duration<double, milli>(t1 - t0).count();
}

// U1: small-range update (on 2019-07-10, pc>=2, tip<20): tip += 0.01; simulate
// ROLLBACK via copy
static double u1_update(const std::vector<Row>& base, long long& target, long long& updated){
    auto t0=clk::now();
    TxView tx(base);
    target=0;

    for (size_t i=0;i<base.size();++i){
        const Row& r = base[i];
        if (on_2019_07_10(r) && r.passenger_count>=2 && r.tip_amount<20.0) target++;
    }
    updated = tx.update(
        [](const Row& r){ return on_2019_07_10(r) && r.passenger_count>=2 && r.tip_amount<20.0; },
        [](Row& r){ r.tip_amount += 0.01; }
    );
    tx.rollback();
    auto t1=clk::now();
    return chrono::duration<double, milli>(t1-t0).count();
}

// U2: medium-range update (1.0<=distance<=3.0): total_amount += 0.01; simulate
// ROLLBACK via copy
static double u2_update(const std::vector<Row>& base, long long& target, long long& updated){
    auto t0=clk::now();
    TxView tx(base);
    target=0;
    for (size_t i=0;i<base.size();++i){
        const Row& r = base[i];
        if (r.trip_distance>=1.0 && r.trip_distance<=3.0) target++;
    }
    updated = tx.update(
        [](const Row& r){ return r.trip_distance>=1.0 && r.trip_distance<=3.0; },
        [](Row& r){ r.total_amount += 0.01; }
    );
    tx.rollback();
    auto t1=clk::now();
    return chrono::duration<double, milli>(t1-t0).count();
}

// U3: sandbox commit  —— copy a slice (2019-07-10), update
// improvement_surcharge += 0.01, then drop
static void u3_sandbox(const vector<Row>& rows, long long& sandbox_rows,
                       double& ctas_ms, long long& updated, double& upd_ms,
                       double& total_ms) {
    auto t0 = clk::now();
    vector<Row> sandbox;
    sandbox.reserve(300000);
    for (const auto& r : rows) {
        if (on_2019_07_10(r)) sandbox.push_back(r);
    }
    sandbox_rows = (long long)sandbox.size();
    auto t1 = clk::now();
    ctas_ms = chrono::duration<double, milli>(t1 - t0).count();

    auto t2 = clk::now();
    updated = 0;
    for (auto& r : sandbox) {
        r.improvement_surcharge = r.improvement_surcharge + 0.01;
        updated++;
    }
    auto t3 = clk::now();
    upd_ms = chrono::duration<double, milli>(t3 - t2).count();

    sandbox.clear();
    sandbox.shrink_to_fit();  // drop
    auto t4 = clk::now();
    total_ms = chrono::duration<double, milli>(t4 - t0).count();
}

struct Args {
    string csv;
    string outdir = "results/toycpp";
    size_t limit_rows = 0;  // all if 0
};
static Args parse_args(int argc, char** argv) {
    Args a;
    for (int i = 1; i < argc; i++) {
        string s = argv[i];
        auto next = [&](string& dst) {
            if (i + 1 < argc) dst = argv[++i];
        };
        if (s == "--csv")
            next(a.csv);
        else if (s == "--out")
            next(a.outdir);
        else if (s == "--limit-rows") {
            string t;
            next(t);
            a.limit_rows = (size_t)stoull(t);
        }
    }
    return a;
}

static void ensure_dir(const string& outdir) {
#ifdef _WIN32
    string cmd =
        "powershell -NoP -C \"New-Item -ItemType Directory -Force -Path '" +
        outdir + "' | Out-Null\"";
#else
    string cmd = "mkdir -p '" + outdir + "'";
#endif
    system(cmd.c_str());
}

int main(int argc, char** argv) {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);

    Args args = parse_args(argc, argv);
    if (args.csv.empty()) {
        cerr << "Usage: toydb --csv <path-to-yellow_2019_07.csv> [--out "
                "results/toycpp] [--limit-rows N]\n";
        return 2;
    }
    ensure_dir(args.outdir);

    auto t0 = clk::now();
    auto rows = load_csv(args.csv, args.limit_rows);
    auto t1 = clk::now();
    double load_ms = chrono::duration<double, milli>(t1 - t0).count();

    BenchOut B{};
    B.dataset_rows = (long long)rows.size();

    size_t groups = 0, top = 0;
    B.q1_ms = q1_hourly(rows, groups);
    B.q2_ms = q2_top100(rows);
    B.q3_ms = q3_locagg(rows, top);

    B.u1_ms = u1_update(rows, B.u1_target, B.u1_update_rows);
    B.u2_ms = u2_update(rows, B.u2_target, B.u2_update_rows);
    u3_sandbox(rows, B.u3_ctas_rows, B.u3_ctas_ms, B.u3_update_rows,
               B.u3_update_ms, B.u3_total_ms);

    // —— 构造人类可读的摘要
    ostringstream sb;
    sb << "Loaded rows: " << B.dataset_rows << " in " << load_ms << " ms\n"
       << "Q1 " << B.q1_ms << " ms, Q2 " << B.q2_ms << " ms, Q3 " << B.q3_ms
       << " ms\n"
       << "U1 target " << B.u1_target << " update " << B.u1_update_rows
       << " in " << B.u1_ms << " ms\n"
       << "U2 target " << B.u2_target << " update " << B.u2_update_rows
       << " in " << B.u2_ms << " ms\n"
       << "U3 CTAS " << B.u3_ctas_rows << " in " << B.u3_ctas_ms
       << " ms; UPDATE " << B.u3_update_rows << " in " << B.u3_update_ms
       << " ms; total " << B.u3_total_ms << " ms\n";

    cout << sb.str();

    string outcsv = args.outdir + "/metrics_toycpp.csv";
    bool need_header = false;
    {
        ifstream fin(outcsv);
        if (!fin.good()) need_header = true;
    }

    ofstream fout(outcsv, ios::app);
    if (!fout) {
        cerr << "ERR: cannot write " << outcsv << "\n";
        return 3;
    }
    if (need_header) {
        fout << "impl,profile,cache,run,ts,work_mem,dataset_rows,load_ms,"
                "q1_ms,q2_ms,q3_ms,"
                "u1_target,u1_update_rows,u1_ms,"
                "u2_target,u2_update_rows,u2_ms,"
                "u3_ctas_rows,u3_ctas_ms,u3_update_rows,u3_update_ms,u3_total_"
                "ms\n";
    }
    fout << "toycpp,default,na,1,NA,NA," << B.dataset_rows << "," << load_ms
         << "," << B.q1_ms << "," << B.q2_ms << "," << B.q3_ms << ","
         << B.u1_target << "," << B.u1_update_rows << "," << B.u1_ms << ","
         << B.u2_target << "," << B.u2_update_rows << "," << B.u2_ms << ","
         << B.u3_ctas_rows << "," << B.u3_ctas_ms << "," << B.u3_update_rows
         << "," << B.u3_update_ms << "," << B.u3_total_ms << "\n";

    cout<<outcsv<<endl;
    return 0;
}
