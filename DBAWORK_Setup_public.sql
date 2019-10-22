USE msdb
GO
SET NOCOUNT ON

/************************************************************************
 * Adds DBAWORK database and monitoring jobs to new servers.

  Modify DL-DataServices@ to your email address before running

 ************************************************************************/



---------------------------------------------------------
--              CREATE SQL ADMIN OPERATOR
---------------------------------------------------------
IF  (EXISTS (SELECT name FROM msdb.dbo.sysoperators WHERE name = N'Data Services'))
BEGIN
        PRINT 'Data Services already exists as an operator'
END
ELSE

		EXEC msdb.dbo.sp_add_operator @name=N'Data Services', 
                @enabled                        = 1, 
                @weekday_pager_start_time       = 0, 
                @weekday_pager_end_time         = 235959, 
                @saturday_pager_start_time      = 0, 
                @saturday_pager_end_time        = 235959, 
                @sunday_pager_start_time        = 0, 
                @sunday_pager_end_time          = 235959, 
                @pager_days                     = 127, 
				@email_address=N'DL-DataServices@',
				@pager_address=N'DL-DataServices@'
GO


---------------------------------------------------------
--              CREATE DBAWORK DATABASE
---------------------------------------------------------
IF EXISTS (SELECT name FROM master.dbo.sysdatabases WHERE name = N'DBAWORK')
BEGIN
     PRINT 'DBAWORK already exists'
END
ELSE
BEGIN
CREATE DATABASE DBAWORK
--GO
ALTER DATABASE DBAWORK MODIFY FILE (NAME = DBAWORK, 	NEWNAME = DBAWORK_data,	SIZE = 256MB, FILEGROWTH = 128)
--GO
EXEC DBAWORK..sp_changedbowner 'sa'
--GO
END
GO




---------------------------------------------------------
--              CREATE DBAWORK TABLES
---------------------------------------------------------
USE DBAWORK
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[tb_database_status_checker]') AND type in (N'U'))
BEGIN
	DROP TABLE tb_database_status_checker
	PRINT 'dropping table tb_database_status_checker'
END
GO

CREATE TABLE tb_database_status_checker
	(
	row_id                  	INT     IDENTITY(1,1),
	database_id			VARCHAR(10),
	database_name			VARCHAR(256),
	database_online			CHAR(1),
	transaction_time		DATETIME
	)
GO

IF EXISTS (SELECT * FROM DBAWORK.dbo.sysobjects WHERE name = 'tb_job_status_checker')
BEGIN
        DROP TABLE dbo.tb_job_status_checker
        PRINT 'dropping table tb_job_status_checker'        
END
GO

CREATE TABLE tb_job_status_checker 
        (
        row_id                  	INT     IDENTITY(1,1),
        job_id                		VARCHAR(50),
        job_name              		VARCHAR(256),
        job_status           	 	CHAR(1),
        transaction_time      		DATETIME 
        ) 
GO
IF EXISTS (SELECT * FROM DBAWORK.dbo.sysobjects WHERE name = 'tb_sysalerts')
BEGIN
        DROP TABLE tb_sysalerts
        PRINT 'dropping table tb_sysalerts'
END     
GO

CREATE TABLE tb_sysalerts
        (
		row_id		                  	INT     IDENTITY(1,1),
        id                              INT,
        name                            NVARCHAR(128),
        event_source                    NVARCHAR(100),
        event_category_id               INT,
        event_id                        INT,
        message_id                      INT,
        severity                        INT,
        notification_message            NVARCHAR(512),
        include_event_description       TINYINT,
        database_name                   NVARCHAR(128),
        event_description_keyword       NVARCHAR(100),
        job_id                          uniqueidentifier,
        has_notification                INT,
        flags                           INT,
        performance_condition           NVARCHAR(512),
        category_id                     INT
        )
GO

IF EXISTS (SELECT * FROM DBAWORK.dbo.sysobjects WHERE name = 'tb_sysalerts_work')
BEGIN
        DROP TABLE tb_sysalerts_work
        PRINT 'dropping table tb_sysalerts_work'
END     
GO
CREATE TABLE tb_sysalerts_work 
        (
      --  row_id                  	INT     IDENTITY(1,1),
        id                              INT,
        name                            NVARCHAR(128),
        orig_name                       NVARCHAR(128),
        event_source                    NVARCHAR(100),
        orig_event_source               NVARCHAR(100),
        event_category_id               INT,
        orig_event_category_id          INT,
        event_id                        INT,
        orig_event_id                   INT,
        message_id                      INT,
        orig_message_id                 INT,
        severity                        INT,
        orig_severity                   INT,
        notification_message            NVARCHAR(512),
        orig_notification_message       NVARCHAR(512),
        include_event_description       TINYINT,
        orig_include_event_description  TINYINT,
        database_name                   NVARCHAR(128),
        orig_database_name              NVARCHAR(128),
        event_description_keyword       NVARCHAR(100),
        orig_event_description_keyword  NVARCHAR(100),
        job_id                          uniqueidentifier,
        orig_job_id                     uniqueidentifier,
        has_notification                INT,
        orig_has_notification           INT,
        flags                           INT,
        orig_flags                      INT,
        performance_condition           NVARCHAR(512),
        orig_performance_condition      NVARCHAR(512),
        category_id                     INT,
        orig_category_id                INT
        ) 
GO

IF EXISTS (SELECT * FROM DBAWORK.dbo.sysobjects WHERE name = 'tb_sysalerts_summary')
BEGIN
        DROP TABLE tb_sysalerts_summary
        PRINT 'dropping table tb_sysalerts_summary'
END     
GO

CREATE TABLE tb_sysalerts_summary 
        (
        row_id                  	INT     IDENTITY(1,1),
        id              		INT,
        column_name     		VARCHAR(32),
        value_one       		VARCHAR(512),
        value_two       		VARCHAR(512)   
        )
GO

IF EXISTS (SELECT * FROM DBAWORK.dbo.sysobjects WHERE name = 'tb_databases')
        BEGIN
                DROP TABLE DBAWORK.dbo.tb_databases
                PRINT 'DROPPED tb_databases From DBAWORK'
        END
GO

CREATE TABLE tb_databases
        (
        row_id                  	INT     IDENTITY(1,1),
        database_name           	SYSNAME,
        database_size_in_kb     	INT,                            -- Size of database, in kilobytes.
        remarks                 	VARCHAR(254)
        )
GO



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[bp_database_status_checker]') AND type in (N'P', N'PC'))
BEGIN
	DROP PROCEDURE [dbo].[bp_database_status_checker]
	PRINT 'dropping procedure [bp_database_status_checker]'
END
GO

CREATE PROCEDURE bp_database_status_checker AS

BEGIN

SET NOCOUNT ON

-- variable declaration
-----------------------
DECLARE @email_profile	VARCHAR(100),
	@email_address  VARCHAR(50),
        @email_subject  VARCHAR(100),
        @email_message  VARCHAR(150),
        @database_name	VARCHAR(100),
        @name           VARCHAR(100)

SET	@email_profile	= REPLACE(@@SERVERNAME, '\','$')
SET     @email_address	= 'DL-DataServices@'

-- missing databases
--------------------
SELECT  @email_subject  = @@SERVERNAME +' Database Check - Missing Database(s)'

DECLARE input_cursor CURSOR FOR
        SELECT  database_name
        FROM    DBAWORK.dbo.tb_database_status_checker
        WHERE   database_online = 'Y'

OPEN    input_cursor
FETCH   input_cursor
INTO    @database_name

WHILE ( @@fetch_status = 0 )
    BEGIN
        IF NOT EXISTS (SELECT * FROM master.dbo.sysdatabases WHERE name = @database_name AND DATABASEPROPERTYEX(@database_name, 'STATUS') = 'ONLINE')
        BEGIN
		SELECT	@email_message = @database_name + ' Is Missing or Currently Unavailable With A Status Of ' + ISNULL(CAST(DATABASEPROPERTYEX(@database_name, 'STATUS') AS VARCHAR(25)), 'UNKNOWN') + '; Please Investigate!'
                EXEC	msdb.dbo.sp_send_dbmail
                        @profile_name   = @email_profile,
                        @recipients     = @email_address,
                        @body           = @email_message,
                        @subject        = @email_subject,
                        @importance	= 'HIGH'
        END
        FETCH   input_cursor
        INTO    @database_name
    END

-- clean up
-----------
CLOSE           input_cursor
DEALLOCATE      input_cursor

-- new databases
----------------
SELECT @email_subject  = @@SERVERNAME +' Database Check - New Database(s)'

DECLARE input_cursor CURSOR FOR
        SELECT  name 
        FROM    master.dbo.sysdatabases

OPEN input_cursor

FETCH   input_cursor
INTO    @name

WHILE ( @@fetch_status = 0 )
    BEGIN
        IF NOT EXISTS (SELECT * FROM DBAWORK.dbo.tb_database_status_checker WHERE database_name = @name )
        BEGIN
		SELECT	@email_message	= '' + @name +' Is Missing From tb_database_status_checker, Please Run The ''Database Check Table Refresh'' Job'
		EXEC	msdb.dbo.sp_send_dbmail
                        @profile_name   = @email_profile,
                        @recipients     = @email_address,
                        @body           = @email_message,
                        @subject        = @email_subject,
                        @importance	= 'HIGH'
        END
        FETCH   input_cursor
        INTO    @name
    END

-- clean up
-----------
CLOSE           input_cursor
DEALLOCATE      input_cursor

SET NOCOUNT OFF
END
GO



IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[bp_database_status_checker_refresh]') AND type in (N'P', N'PC'))
BEGIN
	DROP PROCEDURE [dbo].[bp_database_status_checker_refresh]
	PRINT 'dropping procedure [bp_database_status_checker_refresh]'
END
GO

CREATE PROCEDURE bp_database_status_checker_refresh AS

BEGIN
SET NOCOUNT ON

-- clear table
--------------
TRUNCATE TABLE  DBAWORK.dbo.tb_database_status_checker

-- populate table
-----------------
INSERT INTO     DBAWORK.dbo.tb_database_status_checker (database_id, database_name, database_online, transaction_time)
SELECT  dbid						as database_id, 
        name						as database_name, 
	CASE DATABASEPROPERTYEX(name, 'STATUS')
	WHEN 'ONLINE' THEN 'Y'
	ELSE 'N'
	END						as database_online, 
	GETDATE()					as transaction_time

FROM    master.dbo.sysdatabases

SET NOCOUNT OFF
END
GO



if exists (select * from dbo.sysobjects where id = object_id(N'dbo.bp_job_status_checker') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
        DROP PROCEDURE bp_job_status_checker
        PRINT 'dropping procedure bp_job_status_checker'
END
GO

CREATE PROCEDURE bp_job_status_checker AS

BEGIN

SET NOCOUNT ON

-- variable declaration
-----------------------
DECLARE @email_profile	VARCHAR(100),
	@email_address  VARCHAR(50),
        @email_subject  VARCHAR(100),
        @email_message  VARCHAR(150),
        @job_name       VARCHAR(100),
        @name           VARCHAR(100)

SET	@email_profile	= REPLACE(@@SERVERNAME, '\','$')
SET     @email_address	= 'DL-DataServices@'

-- missing tasks
-----------------
SELECT  @email_subject  = @@SERVERNAME +' Job Check - Missing Jobs'
DECLARE input_cursor CURSOR FOR
        SELECT  job_name
        FROM    DBAWORK.dbo.tb_job_status_checker
        WHERE   job_status = 'Y'

OPEN    input_cursor
FETCH   input_cursor
INTO    @job_name

WHILE ( @@fetch_status = 0 )
    BEGIN
        IF NOT EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = @job_name and enabled = 1 )
        BEGIN
           SELECT       @email_message = @job_name +' Is Missing or Disabled'
                        EXEC msdb.dbo.sp_send_dbmail
                                @profile_name   = @email_profile,
                                @recipients     = @email_address,
                                @body           = @email_message,
                                @subject        = @email_subject;        
        END
        FETCH   input_cursor
        INTO    @job_name
    END

-- clean up
-----------
CLOSE           input_cursor
DEALLOCATE      input_cursor

-- new tasks
------------
SELECT @email_subject  = @@SERVERNAME +' Job Check - New Job'

DECLARE input_cursor CURSOR FOR
        SELECT  name 
        FROM    msdb.dbo.sysjobs 
        WHERE   enabled = 1

OPEN input_cursor

FETCH   input_cursor
INTO    @name

WHILE ( @@fetch_status = 0 )
    BEGIN
        IF NOT EXISTS (SELECT * FROM DBAWORK.dbo.tb_job_status_checker WHERE job_name = @name )
        BEGIN
           SELECT       @email_message = '' + @name +' Is Missing From tb_job_status_checker, Please Run The ''Job Check Table Refresh'' Job'
                        EXEC msdb.dbo.sp_send_dbmail
                                @profile_name   = @email_profile,
                                @recipients     = @email_address,
                                @body           = @email_message,
                                @subject        = @email_subject;
        END
        FETCH   input_cursor
        INTO    @name
    END

-- clean up
-----------
CLOSE           input_cursor
DEALLOCATE      input_cursor

SET NOCOUNT OFF
END
GO



if exists (select * from dbo.sysobjects where id = object_id(N'dbo.bp_job_status_checker_refresh') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN        
        DROP PROCEDURE bp_job_status_checker_refresh
        PRINT 'dropping procedure bp_job_status_checker_refresh'        
END
GO

CREATE PROCEDURE bp_job_status_checker_refresh AS

BEGIN

SET NOCOUNT ON

-- clear table
--------------
TRUNCATE TABLE  DBAWORK.dbo.tb_job_status_checker

-- populate table
-----------------
INSERT INTO     DBAWORK.dbo.tb_job_status_checker (job_id, job_name, job_status, transaction_time)
SELECT  job_id				as job_id, 
        name				as name, 
        CASE enabled	WHEN 1 THEN 'Y'
                	WHEN 0 THEN 'N'
                	END		as job_status, 
        GETDATE()			as transaction_time
FROM    msdb.dbo.sysjobs
END
GO


if exists (select * from dbo.sysobjects where id = object_id(N'dbo.bp_mail_check') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
        DROP PROCEDURE dbo.bp_mail_check
        PRINT 'dropping procedure bp_mail_check'        
END
GO

CREATE PROCEDURE bp_mail_check AS

BEGIN

SET NOCOUNT ON

-- variable declaration
------------------------
DECLARE @first_mail_error   INT,           
        @second_mail_error	INT,            
		@email_profile		VARCHAR(100),
        @email_address      VARCHAR(30),
        @email_subject      VARCHAR(100)

SELECT  @email_profile		= REPLACE(@@SERVERNAME, '\','$'),
		@email_address   	= 'DL-DataServices@',
        @email_subject   	= 'SQL Mail For ' + @@SERVERNAME + ' Is Working After Startup'

        WAITFOR DELAY '000:01:00'
        EXEC msdb.dbo.sp_send_dbmail
                @profile_name   = @email_profile,
                @recipients     = @email_address,
                @subject        = @email_subject;

SELECT 	@first_mail_error	= @@ERROR

IF @first_mail_error <> 0 
BEGIN
	GOTO first_mail_error
END
        RETURN 0

first_mail_error:
        WAITFOR DELAY '000:00:20'
        EXEC msdb.dbo.sp_send_dbmail
                @profile_name   = @email_profile,
                @recipients     = @email_address,
                @subject        = @email_subject;

        SELECT @second_mail_error = @@ERROR
        
        IF @second_mail_error <> 0 
        BEGIN
        	GOTO second_mail_error
        END       
        	RETURN 0

second_mail_error:
        BEGIN
                RAISERROR (91100, 16, 1) WITH LOG
        END
        RETURN 0
SET NOCOUNT OFF
END
GO




if exists (select * from dbo.sysobjects where id = object_id(N'bp_server_alerts_check') and OBJECTPROPERTY(id, N'IsProcedure') = 1)
BEGIN
        DROP PROCEDURE bp_server_alerts_check
        PRINT 'dropping procedure bp_server_alerts_check'
END
GO

CREATE PROCEDURE bp_server_alerts_check @refresh_alerts VARCHAR(6) = NULL AS

BEGIN
SET NOCOUNT ON

DECLARE @columns        INT, -- Holds the number of columns in the tb_sysalerts_work table.
        @runner         INT, -- Iteration variable.
        @col_name       VARCHAR(32),
        @col_name2      VARCHAR(32)

DECLARE @email_profile	VARCHAR(100),
	@email_address  VARCHAR(50),
        @email_subject  VARCHAR(100),
        @email_message  VARCHAR(300),
        @email_query    VARCHAR(800)

SELECT  @email_profile	= REPLACE(@@SERVERNAME, '\','$'),
	@email_address	= 'DL-DataServices@'


IF @refresh_alerts = 'TRUE'
        BEGIN
                DELETE DBAWORK.dbo.tb_sysalerts
                INSERT INTO DBAWORK.dbo.tb_sysalerts 
                                                (
                                                id, name, event_source, event_category_id, event_id, message_id, severity, 
                                                notification_message, include_event_description, database_name,         
                                                event_description_keyword, job_id, has_notification, flags, performance_condition, category_id
                                                )
                SELECT  id, name, event_source, event_category_id, event_id, message_id, severity, notification_message, include_event_description, 
                        database_name, event_description_keyword, job_id, has_notification, flags, performance_condition, category_id 
                FROM    msdb.dbo.sysalerts
                WHERE   enabled = 1
                PRINT 'Refreshing Alerts'
        END
ELSE
        BEGIN
        -- clear work tables
        ---------------------
        TRUNCATE TABLE DBAWORK.dbo.tb_sysalerts_work
        TRUNCATE TABLE DBAWORK.dbo.tb_sysalerts_summary
        
                -- Check for missing alerts:
                ----------------------------------------------------------------
                INSERT INTO DBAWORK.dbo.tb_sysalerts_work (id, name)
                SELECT  a.id, 
                        a.name
                FROM    DBAWORK.dbo.tb_sysalerts               a 
                        LEFT OUTER JOIN msdb.dbo.sysalerts      b ON a.id = b.id
                WHERE   a.id            IS NULL or 
                        b.enabled       = 0
        
                IF (SELECT COUNT(*) FROM DBAWORK.dbo.tb_sysalerts_work) > 0
                BEGIN
                        SELECT  @email_subject   = @@SERVERNAME + ' Server Alerts Check - Missing/Disabled Alert(s)',
                                @email_query     = 'SET NOCOUNT ON; SELECT id as [Alert ID], CAST(SUBSTRING(name, 1, 60) as CHAR(100)) as [Alert Name] FROM DBAWORK.dbo.tb_sysalerts_work',
                                @email_message   = 'The Following Alerts Are Either Missing or Disabled:'        + CHAR(10) + 
                                                  '----------------------------------------------------'        + CHAR(10)
        
                        EXEC    msdb..sp_send_dbmail
                                @profile_name   	= @email_profile,
                                @recipients     	= @email_address,
                                @query          	= @email_query,
                                @subject        	= @email_subject,
                                @body           	= @email_message,
        			@query_result_width	= 120
        
                        TRUNCATE TABLE DBAWORK.dbo.tb_sysalerts_work
                END
        
                -- Check for new alerts:
                ----------------------------------------------------------------
                INSERT INTO DBAWORK.dbo.tb_sysalerts_work (id, name)
                SELECT  a.id, 
                        a.name
                FROM    msdb.dbo.sysalerts                              a 
                        LEFT OUTER JOIN DBAWORK.dbo.tb_sysalerts       b ON a.id = b.id
                WHERE   b.id            IS null and 
                        a.enabled       = 1
        
                IF (SELECT count(*) FROM DBAWORK.dbo.tb_sysalerts_work) > 0
                BEGIN
                        SELECT  @email_subject   = @@SERVERNAME + ' Server Alerts Check - New/Enabled Alert(s)',
                                @email_query     = 'SET NOCOUNT ON; SELECT id as [Alert ID], CAST(SUBSTRING(name, 1, 60) as CHAR(100)) as [Alert Name] FROM DBAWORK.dbo.tb_sysalerts_work',
                                @email_message   = 'The Following Alerts Are Either New or Enabled:'     + CHAR(10) + 
                                                  '----------------------------------------------'      + CHAR(10)

                        EXEC    msdb..sp_send_dbmail
                                @profile_name   	= @email_profile,
                                @recipients     	= @email_address,
                                @query          	= @email_query,
                                @subject        	= @email_subject,
                                @body           	= @email_message,
        			@query_result_width	= 120
        
                        TRUNCATE TABLE DBAWORK.dbo.tb_sysalerts_work
                END
        
                -- Check for altered alerts:
                ----------------------------------------------------------------
                INSERT INTO DBAWORK.dbo.tb_sysalerts_work
                SELECT  m.id, 
                        m.name, 
                        db.name, 
                        m.event_source, 
                        db.event_source, 
                        m.event_category_id,
                        db.event_category_id, 
                        m.event_id, 
                        db.event_id, 
                        m.message_id,
                        db.message_id,  
                        m.severity, 
                        db.severity,
                        m.notification_message, 
                        db.notification_message, 
                        m.include_event_description,
                        db.include_event_description, 
                        m.database_name, 
                        db.database_name, 
                        m.event_description_keyword,
                        db.event_description_keyword, 
                        m.job_id, 
                        db.job_id, 
                        m.has_notification,
                        db.has_notification, 
                        m.flags, 
                        db.flags, 
                        m.performance_condition,
                        db.performance_condition, 
                        m.category_id, 
                        db.category_id
                FROM    msdb.dbo.sysalerts                      m 
                        INNER JOIN DBAWORK.dbo.tb_sysalerts    db ON m.id = db.id
                WHERE   (m.name                         <> db.name)                             or 
                        (m.event_source                 <> db.event_source)                     or 
                        (m.event_category_id            <> db.event_category_id)                or 
                        (m.event_id                     <> db.event_id)                         or 
                        (m.message_id                   <> db.message_id)                       or 
                        (m.severity                     <> db.severity)                         or 
                        (m.notification_message         <> db.notification_message)             or 
                        (m.include_event_description    <> db.include_event_description)        or 
                        (m.database_name                <> db.database_name)                    or 
                        (m.event_description_keyword    <> db.event_description_keyword)        or 
                        (m.job_id                       <> db.job_id)                           or 
                        (m.has_notification             <> db.has_notification)                 or 
                        (m.flags                        <> db.flags)                            or 
                        (m.performance_condition        <> db.performance_condition)            or 
                        (m.category_id                  <> db.category_id)              


                IF (SELECT COUNT(*) FROM DBAWORK.dbo.tb_sysalerts_work) > 0
                BEGIN
                        SELECT @columns = (SELECT MAX(colid) FROM DBAWORK.dbo.syscolumns WHERE id = OBJECT_ID('tb_sysalerts_work'))
                        SELECT @runner  = 2
                        
                        WHILE (@runner <= @columns)
                        BEGIN
                                SELECT @col_name  = (SELECT COL_NAME(OBJECT_ID('tb_sysalerts_work'), @runner))
                                SELECT @col_name2 = (SELECT COL_NAME(OBJECT_ID('tb_sysalerts_work'), @runner + 1))
                                
                                EXEC('INSERT INTO tb_sysalerts_summary SELECT id, ''' + @col_name + ''', ' + @col_name2 + ', ' + @col_name + ' FROM tb_sysalerts_work WHERE ' + @col_name + ' <> ' + @col_name2)
                
                                SELECT @runner = @runner + 2
                        END
                        SELECT  @email_subject   = @@SERVERNAME + ' Server Alerts Check - Alert Altered',
                                @email_query     =       'SET NOCOUNT ON; SELECT CAST(b.name as CHAR(35))      as [Alert Name],'       + CHAR(10) + 
                                                        '       CAST(column_name  as CHAR(10))                     as [Column Name],'      + CHAR(10) + 
                                                        '       CAST(SUBSTRING(a.value_one, 1, 100) as CHAR(35))    as [Before],'           + CHAR(10) + 
                                                        '       CAST(SUBSTRING(a.value_two, 1, 100) as CHAR(35))    as [After]'             + CHAR(10) + 
                                                        'FROM   DBAWORK.dbo.tb_sysalerts_summary as a'                                + CHAR(10) + 
                                                        '       INNER JOIN DBAWORK.dbo.tb_sysalerts as b on a.id = b.id'              + CHAR(10) + 
                                                        'ORDER BY a.id, a.column_name',

        
                                @email_message   = 'The Following Alerts Are Have Been Altered:'                                        + CHAR(10) + 
                                                  '-------------------------------------------'                                         + CHAR(10)

                        EXEC    msdb..sp_send_dbmail
                                @profile_name           = @email_profile, 
                                @recipients             = @email_address,
                                @query                  = @email_query,
                                @subject                = @email_subject,
                                @body                   = @email_message,
                                @query_result_width     = 200
                END
        END

SET NOCOUNT OFF
END
GO



---------------------------------------------------------
--              CREATE DBAWORK JOBS
---------------------------------------------------------
USE [msdb]
GO

IF  EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'DBAWORK - Job Check')
        EXEC msdb.dbo.sp_delete_job @job_name = N'DBAWORK - Job Check', @delete_unused_schedule=1
GO

IF  EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'DBAWORK - Job Check Table Refresh')
        EXEC msdb.dbo.sp_delete_job @job_name = N'DBAWORK - Job Check Table Refresh', @delete_unused_schedule=1
GO

IF  EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'DBAWORK - SQL Server Alerts Check')
        EXEC msdb.dbo.sp_delete_job @job_name = N'DBAWORK - SQL Server Alerts Check', @delete_unused_schedule=1
GO

IF  EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'DBAWORK - SQL Server Alerts Check Refresh')
        EXEC msdb.dbo.sp_delete_job @job_name = N'DBAWORK - SQL Server Alerts Check Refresh', @delete_unused_schedule=1
GO


USE [msdb]
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - Job Check', 
                @enabled=1, 
                @notify_level_eventlog=2, 
                @notify_level_email=2, 
                @notify_level_netsend=0, 
                @notify_level_page=0, 
                @delete_level=0, 
                @description=N'Monitors SQL Job Statuses And Looks For Changes Regarding If The Job Is New, Disabled And/Or Enabled Against A Reference Table.', 
                @category_name=N'Database Maintenance', 
                @owner_login_name=N'sa', 
                @notify_email_operator_name=N'Data Services', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Task Check', 
                @step_id=1, 
                @cmdexec_success_code=0, 
                @on_success_action=1, 
                @on_success_step_id=0, 
                @on_fail_action=2, 
                @on_fail_step_id=0, 
                @retry_attempts=0, 
                @retry_interval=1, 
                @os_run_priority=0, @subsystem=N'TSQL', 
                @command=N'EXEC DBAWORK.dbo.bp_job_status_checker', 
                @database_name=N'DBAWORK', 
                @flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'6 Hours', 
                @enabled=1, 
                @freq_type=4, 
                @freq_interval=1, 
                @freq_subday_type=8, 
                @freq_subday_interval=6, 
                @freq_relative_interval=0, 
                @freq_recurrence_factor=0, 
                @active_start_date=20011115, 
                @active_end_date=99991231, 
                @active_start_time=0, 
                @active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - Job Check Table Refresh', 
                @enabled=0, 
                @notify_level_eventlog=2, 
                @notify_level_email=2, 
                @notify_level_netsend=0, 
                @notify_level_page=0, 
                @delete_level=0, 
                @description=N'Refreshes The Refrence Table', 
                @category_name=N'Database Maintenance', 
                @owner_login_name=N'sa', 
                @notify_email_operator_name=N'Data Services', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Refresh Active Job List', 
                @step_id=1, 
                @cmdexec_success_code=0, 
                @on_success_action=1, 
                @on_success_step_id=0, 
                @on_fail_action=2, 
                @on_fail_step_id=0, 
                @retry_attempts=0, 
                @retry_interval=1, 
                @os_run_priority=0, @subsystem=N'TSQL', 
                @command=N'EXEC DBAWORK.dbo.bp_job_status_checker_refresh', 
                @database_name=N'DBAWORK', 
                @flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - SQL Server Alerts Check', 
                @enabled=1, 
                @notify_level_eventlog=2, 
                @notify_level_email=2, 
                @notify_level_netsend=0, 
                @notify_level_page=0, 
                @delete_level=0, 
                @description=N'No description available.', 
                @category_name=N'Database Maintenance', 
                @owner_login_name=N'sa', 
                @notify_email_operator_name=N'Data Services', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Execute Alert Check Procedure', 
                @step_id=1, 
                @cmdexec_success_code=0, 
                @on_success_action=1, 
                @on_success_step_id=0, 
                @on_fail_action=2, 
                @on_fail_step_id=0, 
                @retry_attempts=0, 
                @retry_interval=1, 
                @os_run_priority=0, @subsystem=N'TSQL', 
                @command=N'EXEC bp_server_alerts_check', 
                @database_name=N'DBAWORK', 
                @flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Daily', 
                @enabled=1, 
                @freq_type=4, 
                @freq_interval=1, 
                @freq_subday_type=8, 
                @freq_subday_interval=6, 
                @freq_relative_interval=0, 
                @freq_recurrence_factor=0, 
                @active_start_date=20030820, 
                @active_end_date=99991231, 
                @active_start_time=1500, 
                @active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - SQL Server Alerts Check Refresh', 
                @enabled=0, 
                @notify_level_eventlog=2, 
                @notify_level_email=2, 
                @notify_level_netsend=0, 
                @notify_level_page=0, 
                @delete_level=0, 
                @description=N'No description available.', 
                @category_name=N'Database Maintenance', 
                @owner_login_name=N'sa', 
                @notify_email_operator_name=N'Data Services', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Call Refresh Alerts Table Procedure', 
                @step_id=1, 
                @cmdexec_success_code=0, 
                @on_success_action=1, 
                @on_success_step_id=0, 
                @on_fail_action=2, 
                @on_fail_step_id=0, 
                @retry_attempts=0, 
                @retry_interval=1, 
                @os_run_priority=0, @subsystem=N'TSQL', 
                @command=N'EXEC DBAWORK.dbo.bp_server_alerts_check @refresh_alerts = ''TRUE''', 
                @database_name=N'DBAWORK', 
                @flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


USE [msdb]
GO

IF  EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'DBAWORK - Database Check')
BEGIN 
	EXEC msdb.dbo.sp_delete_job @job_name = N'DBAWORK - Database Check', @delete_unused_schedule=1
	PRINT 'dropping Job DBAWORK - Database Check'
END
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - Database Check', 
		@enabled=1, 
		@notify_level_eventlog=2, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Monitors Database Statuses And Looks For Changes Regarding If The Database Is New, Offline And/Or Available Against A Reference Table.', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'Data Services', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Task Check', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=1, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXEC DBAWORK.dbo.bp_database_status_checker', 
		@database_name=N'DBAWORK', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'6 Hours', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=8, 
		@freq_subday_interval=6, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20011115, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO



USE [msdb]
GO

IF  EXISTS (SELECT job_id FROM msdb.dbo.sysjobs_view WHERE name = N'DBAWORK - Database Check Table Refresh')
BEGIN
	EXEC msdb.dbo.sp_delete_job @job_name=N'DBAWORK - Database Check Table Refresh', @delete_unused_schedule=1
	PRINT 'dropping Job DBAWORK - Database Check Table Refresh'
END
GO


BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'Database Maintenance' AND category_class=1)
BEGIN
EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'Database Maintenance'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'DBAWORK - Database Check Table Refresh', 
		@enabled=0, 
		@notify_level_eventlog=2, 
		@notify_level_email=2, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'Refreshes The Refrence Table', 
		@category_name=N'Database Maintenance', 
		@owner_login_name=N'sa', 
		@notify_email_operator_name=N'Data Services', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Refresh Active Database List', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=1, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'EXEC DBAWORK.dbo.bp_database_status_checker_refresh', 
		@database_name=N'DBAWORK', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:

GO


----------------------------------------------------------------
--KICK OFF THE JOB CHECK TABLE REFRESH JOB TO POPULATE THE TABLE
----------------------------------------------------------------
EXEC msdb.dbo.sp_start_job @job_name = 'DBAWORK - SQL Server Alerts Check Refresh'
GO
EXEC msdb.dbo.sp_start_job @job_name = 'DBAWORK - Job Check Table Refresh'
GO
EXEC msdb.dbo.sp_start_job @job_name = 'DBAWORK - Database Check Table Refresh'
GO




USE msdb

------------------------------------------------------------------------------------------------------------
--                                      RECOVERY MODEL
-- Sets system databases to SIMPLE RECOVERY.
------------------------------------------------------------------------------------------------------------
ALTER DATABASE msdb 	SET RECOVERY SIMPLE
GO
ALTER DATABASE master 	SET RECOVERY SIMPLE
GO
ALTER DATABASE model	SET RECOVERY SIMPLE
GO

------------------------------------------------------------------------------------------------------------
--                                      SIZE SYSTEM DATABASES
-- Alters the size of the system database (msdb, model, master, tempdb)
------------------------------------------------------------------------------------------------------------
-- msdb
------------------------------------------------
IF (SELECT size FROM sys.master_files WHERE name = 'MSDBData') < 16384  --divide by 128 to get MBs
BEGIN
	ALTER DATABASE msdb MODIFY FILE (NAME = MSDBData,       SIZE = 128MB, FILEGROWTH = 64MB)
	PRINT 'msdb .mdf Expanded to 128 mb''s and AUTOGROWTH Enabled'
END

IF (SELECT size FROM sys.master_files WHERE name = 'MSDBLog') < 8192
BEGIN
	ALTER DATABASE msdb MODIFY FILE (NAME = MSDBLog,        SIZE = 64MB, FILEGROWTH = 32MB)
	PRINT 'msdb .ldf Expanded to 64 mb''s and AUTOGROWTH Enabled'
END

------------------------------------------------
-- model
------------------------------------------------
IF (SELECT size FROM sys.master_files WHERE name = 'modeldev') < 512
BEGIN
	ALTER DATABASE model MODIFY FILE (NAME = modeldev,      SIZE = 4MB, FILEGROWTH = 8MB)
	PRINT 'model .mdf Expanded to 4 mb''s'
END

IF (SELECT size FROM sys.master_files WHERE name = 'modellog') < 512
BEGIN
	ALTER DATABASE model MODIFY FILE (NAME = modellog,      SIZE = 4MB, FILEGROWTH = 8MB)
	PRINT 'model .ldf Expanded to 4 mb''s'
END

------------------------------------------------
-- master
------------------------------------------------
IF (SELECT size FROM sys.master_files WHERE name = 'master') < 16384
BEGIN
	ALTER DATABASE master MODIFY FILE (NAME = master,       SIZE = 128MB, FILEGROWTH = 16MB)
	PRINT 'master .mdf Expanded to 128 mb''s'
END

IF (SELECT size FROM sys.master_files WHERE name = 'mastlog') < 16384
BEGIN
	ALTER DATABASE master MODIFY FILE (NAME = mastlog,      SIZE = 128MB, FILEGROWTH = 16MB)
	PRINT 'master .ldf Expanded to 128 mb''s'
END



USE master

EXECUTE sp_configure 'show advanced options', 1
RECONFIGURE WITH OVERRIDE
GO
EXECUTE sp_configure 'Database Mail XPs', 1;
GO
RECONFIGURE WITH OVERRIDE
GO
EXECUTE sp_configure 'show advanced options', 0
RECONFIGURE WITH OVERRIDE
GO



USE master

PRINT '------------------------------------'
PRINT '-- SETTING UP DATABASE MAIL'
PRINT '------------------------------------'

-- profile variables
DECLARE @mail_profile_name              VARCHAR(128)
DECLARE @mail_profile_description       VARCHAR(300)

-- account variables
DECLARE @mail_account_name              VARCHAR(128)
DECLARE @mail_account_description       VARCHAR(300) 
DECLARE @mail_email_address             NVARCHAR(100)
DECLARE @mail_display_name              NVARCHAR(128)
DECLARE @mail_smtp_server_name          NVARCHAR(128)
DECLARE @mail_port_number               INT

-- db_mail variables
DECLARE @mail_test_email_address        VARCHAR(100)
DECLARE @mail_subject                   VARCHAR(100)
DECLARE @mail_body                      VARCHAR(200)
DECLARE @error_message            	VARCHAR(300)

-- setting up variables to define the mail account
SELECT @mail_account_name         	= UPPER(REPLACE(@@SERVERNAME, '\','$'))
SELECT @mail_account_description  	= UPPER(@@SERVERNAME) + '''s Mail Account For Administrative E-mail.'
SELECT @mail_email_address        	= UPPER(REPLACE(@@SERVERNAME, '\','$')) + '@yourdomain.com'
SELECT @mail_display_name         	= UPPER(@@SERVERNAME)
SELECT @mail_smtp_server_name     	= 'smtp.mileskimball.local'
SELECT @mail_port_number          	= 25

-- mail profile name. replace with the name for your profile
SELECT @mail_profile_name         	= REPLACE(@@SERVERNAME, '\','$')
SELECT @mail_profile_description  	= 'Sender Will Be ' + @mail_email_address

-- setting up variables to define the mail message
SELECT @mail_test_email_address   	= 'DL-DataServices@'
SELECT @mail_subject             	= 'Testing Email Account'
SELECT @mail_body                	= 'Testing Email Account'



----------------------------------------------------------------
-- Start a transaction before adding the account and the profile
----------------------------------------------------------------
BEGIN TRANSACTION ;

DECLARE @result INT

------------------
-- Add the account
------------------
EXECUTE @result = msdb.dbo.sysmail_add_account_sp
			@account_name           = @mail_account_name,
			@description            = @mail_account_description,
			@email_address          = @mail_email_address,
			@display_name           = @mail_display_name,
			@mailserver_name        = @mail_smtp_server_name,
			@port                   = @mail_port_number

IF @result <> 0
BEGIN
	SET @error_message       = 'Failed To Create The Specified Database Mail Account ['+ @mail_account_name +'].'
	RAISERROR(@error_message, 16, 1) ;
    GOTO done;
END

------------------
-- Add the profile
------------------
EXECUTE @result = msdb.dbo.sysmail_add_profile_sp
			@profile_name           = @mail_profile_name, 
			@description            = @mail_profile_description

IF @result <> 0
BEGIN
    SET @error_message           = 'Failed To Create The Specified Database Mail Profile ['+ @mail_profile_name +'].'
	RAISERROR(@error_message, 16, 1) ;
	ROLLBACK TRANSACTION;
    GOTO done;
END;

------------------------------------------
-- Associate the account with the profile.
------------------------------------------
EXECUTE @result = msdb.dbo.sysmail_add_profileaccount_sp
			@profile_name           = @mail_profile_name,
			@account_name           = @mail_account_name,
			@sequence_number        = 1;

IF @result <> 0
BEGIN   
	SET @error_message       = 'Failed To Associate The Speficied Profile [' + @mail_profile_name + '] With The Specified Account ['+ @mail_account_name +'].'  
	RAISERROR(@error_message, 16, 1) ;       
ROLLBACK TRANSACTION;
GOTO done;
END;

COMMIT TRANSACTION

done:

IF NOT EXISTS ( SELECT profile_id FROM msdb.dbo.sysmail_principalprofile WHERE [profile_id] in (SELECT profile_id FROM msdb.dbo.sysmail_profile WHERE name =  @mail_profile_name))

	EXECUTE msdb.dbo.sysmail_add_principalprofile_sp  
			@principal_name         = 'public',
			@profile_name           = @mail_profile_name,
			@is_default             = 1;


EXECUTE msdb.dbo.sysmail_start_sp ;

--------------------------------
-- Test that you can send emails
--------------------------------
EXEC    msdb.dbo.sp_send_dbmail 
		@profile_name   = @mail_profile_name,
		@recipients     = @mail_test_email_address,
		@subject        = @mail_subject,
		@body           = @mail_body




-----------------------------------------------------------
-- enables sql agent mail profile and assigns it a profile
-----------------------------------------------------------
EXEC msdb.dbo.sp_set_sqlagent_properties @email_save_in_sent_folder=1, @databasemail_profile=@mail_account_name
GO

PRINT '------------------------------------'
PRINT '-- Changing Server Options'
PRINT '------------------------------------'
-----------------------------------------------------------
-- fail safe on setting max server memory, defaults to half available
-----------------------------------------------------------
EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE
GO
DECLARE	@sql_server_memory	DECIMAL(10,0)
SELECT 	@sql_server_memory 	= CAST( ROUND(physical_memory_kb / 1024.0, 0)  / 2.0 AS INT) FROM sys.dm_os_sys_info

EXEC master.sys.sp_configure N'max server memory (MB)', @sql_server_memory
GO
RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'show advanced options', N'0'  RECONFIGURE WITH OVERRIDE
GO


-----------------------------------------------------------
-- modify other server settings
-----------------------------------------------------------
EXEC sys.sp_configure N'show advanced options', N'1'  RECONFIGURE WITH OVERRIDE
GO

DECLARE	@sql_server_cpus	INT
SELECT 	@sql_server_cpus 	= (SELECT cpu_count FROM sys.dm_os_sys_info)

If @sql_server_cpus > 3
begin
set @sql_server_cpus = @sql_server_cpus/2
end
else
begin
set @sql_server_cpus = 1
end

EXEC master.sys.sp_configure N'Max Degree of Parallelism', @sql_server_cpus
GO
EXEC master.sys.sp_configure N'Optimize for Ad hoc Workloads', 1
GO
EXEC master.sys.sp_configure N'Cost Threshold for Parallelism', 50
GO
EXEC master.sys.sp_configure N'Network Packet Size', 8192
GO
EXEC master.sys.sp_configure N'backup checksum default', 1
GO
RECONFIGURE WITH OVERRIDE
GO
EXEC sys.sp_configure N'show advanced options', N'0'  RECONFIGURE WITH OVERRIDE
GO


-----------------------------------------------------------
-- increase job history size; Todd Palecek added 2/18/16
-----------------------------------------------------------
USE [msdb]
GO
EXEC msdb.dbo.sp_set_sqlagent_properties @jobhistory_max_rows=3000, 
		@jobhistory_max_rows_per_job=200
GO


-----------------------------------------------------------
-- Security hardening added 5/2/19
-----------------------------------------------------------
REVOKE SELECT ON OBJECT::[sys].[database_automatic_tuning_mode] FROM [public]
REVOKE SELECT ON OBJECT::[sys].[database_automatic_tuning_options] FROM [public]
REVOKE SELECT ON OBJECT::[sys].[dm_db_column_store_row_group_physical_stats] FROM [public]
REVOKE SELECT ON OBJECT::[sys].[external_libraries] FROM [public]
REVOKE SELECT ON OBJECT::[sys].[external_library_files] FROM [public]
REVOKE SELECT ON OBJECT::[sys].[index_resumable_operations] FROM [public]
REVOKE SELECT ON OBJECT::[sys].[query_store_wait_stats] FROM [public]

SET NOCOUNT OFF



