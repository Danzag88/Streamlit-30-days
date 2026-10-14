-- Creates the database and schema used to publish the LinkedIn post app.
-- Run this whole file in a Snowsight SQL worksheet while the role is ACCOUNTADMIN.
--
-- After it succeeds, deploy the Streamlit app to:
--   Database: STREAMLIT_APPS
--   Schema:   LINKEDIN
--   Warehouse: COMPUTE_WH

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS STREAMLIT_APPS
    COMMENT = 'Collection of Streamlit apps for the 30 Days of AI course';

CREATE SCHEMA IF NOT EXISTS STREAMLIT_APPS.LINKEDIN
    COMMENT = 'LinkedIn post generator and Cortex AI_COMPLETE calls';

USE SCHEMA STREAMLIT_APPS.LINKEDIN;

-- The trial warehouse that runs AI_COMPLETE and the app queries.
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Query warehouse for the LinkedIn Streamlit app';

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ACCOUNTADMIN;
GRANT USAGE ON DATABASE STREAMLIT_APPS TO ROLE ACCOUNTADMIN;
GRANT USAGE ON SCHEMA STREAMLIT_APPS.LINKEDIN TO ROLE ACCOUNTADMIN;
GRANT CREATE STREAMLIT ON SCHEMA STREAMLIT_APPS.LINKEDIN TO ROLE ACCOUNTADMIN;
GRANT CREATE STAGE ON SCHEMA STREAMLIT_APPS.LINKEDIN TO ROLE ACCOUNTADMIN;

-- Lets the warehouse call Cortex functions such as AI_COMPLETE.
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE ACCOUNTADMIN;

-- This GCP Europe trial reaches Claude in another Snowflake region.
-- The prompt is processed there. Saved data stays in this account.
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- Same call the Streamlit app makes. A short sentence means deploy can proceed.
SELECT AI_COMPLETE('claude-sonnet-4-6', 'Say hello in five words.') AS cortex_check;
