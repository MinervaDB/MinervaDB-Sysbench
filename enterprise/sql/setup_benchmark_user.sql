-- =============================================================================
-- MinervaDB-Sysbench Enterprise — Database User Setup
-- =============================================================================
-- Run as a DBA with SUPER/GRANT OPTION before executing benchmarks.
-- Replace 'StrongPassword!Change#Me' with a strong random password.
-- =============================================================================

-- ============================================================================
-- SECTION A: MySQL / MariaDB Setup
-- ============================================================================

-- Create benchmark schema
CREATE DATABASE IF NOT EXISTS sbtest CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create dedicated benchmark user (restrict to benchmark host IP range)
-- Replace '10.0.%' with your benchmark host CIDR
CREATE USER IF NOT EXISTS 'sbtest'@'10.0.%'
  IDENTIFIED BY 'StrongPassword!Change#Me'
  PASSWORD EXPIRE INTERVAL 90 DAY
  FAILED_LOGIN_ATTEMPTS 5
  PASSWORD_LOCK_TIME 1;

-- Grant minimum required privileges
GRANT CREATE, DROP, INDEX, ALTER, INSERT, UPDATE, DELETE, SELECT
  ON sbtest.* TO 'sbtest'@'10.0.%';

-- Optional: Performance Schema read access for monitoring
GRANT SELECT ON performance_schema.* TO 'sbtest'@'10.0.%';
GRANT SELECT ON sys.* TO 'sbtest'@'10.0.%';

FLUSH PRIVILEGES;

-- Verify grants
SHOW GRANTS FOR 'sbtest'@'10.0.%';

-- ============================================================================
-- SECTION B: Pre-Benchmark Validation Queries (MySQL)
-- ============================================================================

-- Check InnoDB buffer pool free percentage
SELECT ROUND(
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_free') /
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_pages_total') * 100, 2
) AS buffer_pool_free_pct;

-- Check connection utilization
SELECT
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status  WHERE VARIABLE_NAME = 'Threads_connected') AS current_connections,
  (SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME = 'max_connections') AS max_connections;

-- Key configuration snapshot (record before benchmark)
SELECT VARIABLE_NAME, VARIABLE_VALUE
FROM performance_schema.global_variables
WHERE VARIABLE_NAME IN (
  'innodb_buffer_pool_size', 'innodb_log_file_size',
  'innodb_flush_log_at_trx_commit', 'innodb_flush_method',
  'max_connections', 'slow_query_log', 'long_query_time'
)
ORDER BY VARIABLE_NAME;

-- ============================================================================
-- SECTION C: Cleanup (after benchmarking — uncomment when ready)
-- ============================================================================
-- REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'sbtest'@'10.0.%';
-- DROP USER IF EXISTS 'sbtest'@'10.0.%';
-- DROP DATABASE IF EXISTS sbtest;
-- FLUSH PRIVILEGES;

-- ============================================================================
-- SECTION D: PostgreSQL Setup (run in psql, not MySQL)
-- ============================================================================
-- CREATE ROLE sbtest WITH LOGIN PASSWORD 'StrongPassword!Change#Me'
--   CONNECTION LIMIT 200 VALID UNTIL '2027-01-01';
-- CREATE DATABASE sbtest OWNER sbtest ENCODING 'UTF8' TEMPLATE template0;
-- \c sbtest
-- GRANT ALL ON SCHEMA public TO sbtest;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO sbtest;
