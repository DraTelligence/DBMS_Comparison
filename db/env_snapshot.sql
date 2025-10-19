SELECT name, setting
FROM pg_settings
WHERE name IN ('shared_buffers',
               'work_mem',
               'default_statistics_target');