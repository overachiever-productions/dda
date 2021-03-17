

IF OBJECT_ID('dda.remove_obsolete_audit_data','P') IS NOT NULL
	DROP PROC [dda].[remove_obsolete_audit_data];
GO

CREATE PROC [dda].[remove_obsolete_audit_data]
	@DaysWorthOfDataToKeep					int,
	@BatchSize								int			= 2000,
	@WaitForDelay							sysname		= N'00:00:01.500',
	@AllowDynamicBatchSizing				bit			= 1,
	@MaxAllowedBatchSizeMultiplier			int			= 5, 
	@TargetBatchMilliseconds				int			= 2800,
	@MaxExecutionSeconds					int			= NULL,
	@MaxAllowedErrors						int			= 1,
	@TreatDeadlocksAsErrors					bit			= 0,
	@StopIfTempTableExists					sysname		= NULL
AS
    SET NOCOUNT ON; 

	-- NOTE: this code was generated from admindb.dbo.blueprint_for_batched_operation.
	
	-- Parameter Scrubbing/Cleanup:
	SET @WaitForDelay = NULLIF(@WaitForDelay, N'');
	SET @StopIfTempTableExists = ISNULL(@StopIfTempTableExists, N'');
	
	---------------------------------------------------------------------------------------------------------------
	-- Initialization:
	---------------------------------------------------------------------------------------------------------------
	SET NOCOUNT ON; 

	CREATE TABLE [#batched_operation_602436EA] (
		[detail_id] int IDENTITY(1,1) NOT NULL, 
		[timestamp] datetime NOT NULL DEFAULT GETDATE(), 
		[is_error] bit NOT NULL DEFAULT (0), 
		[detail] nvarchar(MAX) NOT NULL
	); 

	-- Processing (variables/etc.)
	DECLARE @dumpHistory bit = 0;
	DECLARE @currentRowsProcessed int = @BatchSize; 
	DECLARE @totalRowsProcessed int = 0;
	DECLARE @errorDetails nvarchar(MAX);
	DECLARE @errorsOccured bit = 0;
	DECLARE @currentErrorCount int = 0;
	DECLARE @deadlockOccurred bit = 0;
	DECLARE @startTime datetime = GETDATE();
	DECLARE @batchStart datetime;
	DECLARE @milliseconds int;
	DECLARE @initialBatchSize int = @BatchSize;
	
	---------------------------------------------------------------------------------------------------------------
	-- Processing:
	---------------------------------------------------------------------------------------------------------------
	WHILE @currentRowsProcessed = @BatchSize BEGIN 
	
		SET @batchStart = GETDATE();
	
		BEGIN TRY
			BEGIN TRAN; 
				
				-------------------------------------------------------------------------------------------------
				-- batched operation code:
				-------------------------------------------------------------------------------------------------
				DELETE [t]
				FROM dda.[audits] t WITH(ROWLOCK)
				INNER JOIN (
					SELECT TOP (@BatchSize) 
						[audit_id]  
					FROM 
						dda.[audits] WITH(NOLOCK)  
					WHERE 
						[timestamp] < DATEADD(DAY, 0 - @DaysWorthOfDataToKeep, @startTime) 
					) x ON t.[audit_id]= x.[audit_id]; 

				-------------------------------------------
				SELECT 
					@currentRowsProcessed = @@ROWCOUNT, 
					@totalRowsProcessed = @totalRowsProcessed + @@ROWCOUNT;

			COMMIT; 

			INSERT INTO [#batched_operation_602436EA] (
				[timestamp],
				[detail]
			)
			SELECT 
				GETDATE() [timestamp], 
				(
					SELECT 
						@BatchSize [settings.batch_size], 
						@WaitForDelay [settings.wait_for], 
						@currentRowsProcessed [progress.current_batch_count], 
						@totalRowsProcessed [progress.total_rows_processed],
						DATEDIFF(MILLISECOND, @batchStart, GETDATE()) [progress.batch_milliseconds], 
						DATEDIFF(MILLISECOND, @startTime, GETDATE())[progress.total_milliseconds]
					FOR JSON PATH, ROOT('detail')
				) [detail];

			IF @MaxExecutionSeconds > 0 AND (DATEDIFF(SECOND, @startTime, GETDATE()) >= @MaxExecutionSeconds) BEGIN 
				INSERT INTO [#batched_operation_602436EA] (
					[timestamp],
					[is_error],
					[detail]
				)
				SELECT
					GETDATE() [timestamp], 
					1 [is_error], 
					( 
						SELECT 
							@currentRowsProcessed [progress.current_batch_count], 
							@totalRowsProcessed [progress.total_rows_processed],
							DATEDIFF(MILLISECOND, @batchStart, GETDATE()) [progress.batch_milliseconds], 
							DATEDIFF(MILLISECOND, @startTime, GETDATE())[progress.total_milliseconds],
							CONCAT(N'Maximum execution seconds allowed for execution met/exceeded. Max Allowed Seconds: ', @MaxExecutionSeconds, N'.') [errors.error]
						FOR JSON PATH, ROOT('detail')
					) [detail];
			
				SET @errorsOccured = 1;

				GOTO Finalize;		
			END;

			IF OBJECT_ID(N'tempdb..' + @StopIfTempTableExists) IS NOT NULL BEGIN 
				INSERT INTO [#batched_operation_602436EA] (
					[timestamp],
					[is_error],
					[detail]
				)
				SELECT
					GETDATE() [timestamp], 
					1 [is_error], 
					( 
						SELECT 
							@currentRowsProcessed [progress.current_batch_count], 
							@totalRowsProcessed [progress.total_rows_processed],
							DATEDIFF(MILLISECOND, @batchStart, GETDATE()) [progress.batch_milliseconds], 
							DATEDIFF(MILLISECOND, @startTime, GETDATE())[progress.total_milliseconds],
							N'Graceful execution shutdown/bypass directive detected - object [' + @StopIfTempTableExists + N'] found in tempdb. Terminating Execution.' [errors.error]
						FOR JSON PATH, ROOT('detail')
					) [detail];
			
				SET @errorsOccured = 1;

				GOTO Finalize;
			END;

			-- Dynamic Tuning:
			SET @milliseconds = DATEDIFF(MILLISECOND, @batchStart, GETDATE());
			IF @milliseconds <= @TargetBatchMilliseconds BEGIN 
				IF @BatchSize < (@initialBatchSize * @MaxAllowedBatchSizeMultiplier) BEGIN

					SET @BatchSize = FLOOR((@BatchSize + (@BatchSize * .2)) / 100) * 100; 
					IF @BatchSize > (@initialBatchSize * @MaxAllowedBatchSizeMultiplier) 
						SET @BatchSize = (@initialBatchSize * @MaxAllowedBatchSizeMultiplier);
				END;
			  END;
			ELSE BEGIN 
				IF @BatchSize > (@initialBatchSize / @MaxAllowedBatchSizeMultiplier) BEGIN

					SET @BatchSize = FLOOR((@BatchSize - (@BatchSize * .2)) / 100) * 100;
					IF @BatchSize < (@initialBatchSize / @MaxAllowedBatchSizeMultiplier)
						SET @BatchSize = (@initialBatchSize / @MaxAllowedBatchSizeMultiplier);
				END;
			END; 
		
			WAITFOR DELAY @WaitForDelay;
		END TRY
		BEGIN CATCH 
			
			IF ERROR_NUMBER() = 1205 BEGIN
		
				INSERT INTO [#batched_operation_602436EA] (
					[timestamp],
					[is_error],
					[detail]
				)
				SELECT
					GETDATE() [timestamp], 
					1 [is_error], 
					( 
						SELECT 
							@currentRowsProcessed [progress.current_batch_count], 
							@totalRowsProcessed [progress.total_rows_processed],
							N'Deadlock Detected. Logging to history table - but not counting deadlock as normal error for purposes of error handling/termination.' [errors.error]
						FOR JSON PATH, ROOT('detail')
					) [detail];
					   
				SET @deadlockOccurred = 1;		
			END; 

			SELECT @errorDetails = N'Error Number: ' + CAST(ERROR_NUMBER() AS sysname) + N'. Message: ' + ERROR_MESSAGE();

			IF @@TRANCOUNT > 0
				ROLLBACK; 

			INSERT INTO [#batched_operation_602436EA] (
				[timestamp],
				[is_error],
				[detail]
			)
			SELECT
				GETDATE() [timestamp], 
				1 [is_error], 
				( 
					SELECT 
						@currentRowsProcessed [progress.current_batch_count], 
						@totalRowsProcessed [progress.total_rows_processed],
						N'Unexpected Error Occurred: ' + @errorDetails [errors.error]
					FOR JSON PATH, ROOT('detail')
				) [detail];
					   
			SET @errorsOccured = 1;
		
			SET @currentErrorCount = @currentErrorCount + 1; 
			IF @currentErrorCount >= @MaxAllowedErrors BEGIN 
				INSERT INTO [#batched_operation_602436EA] (
					[timestamp],
					[is_error],
					[detail]
				)
				SELECT
					GETDATE() [timestamp], 
					1 [is_error], 
					( 
						SELECT 
							@currentRowsProcessed [progress.current_batch_count], 
							@totalRowsProcessed [progress.total_rows_processed],
							CONCAT(N'Max allowed errors count reached/exceeded: ', @MaxAllowedErrors, N'. Terminating Execution.') [errors.error]
						FOR JSON PATH, ROOT('detail')
					) [detail];

				GOTO Finalize;
			END;
		END CATCH;
	END;

	---------------------------------------------------------------------------------------------------------------
	-- Finalization/Reporting:
	---------------------------------------------------------------------------------------------------------------

Finalize:

	IF @deadlockOccurred = 1 BEGIN 
		PRINT N'NOTE: One or more deadlocks occurred.'; 
		SET @dumpHistory = 1;
	END;

	IF @errorsOccured = 1 BEGIN 
		SET @dumpHistory = 1;
	END;

	IF @dumpHistory = 1 BEGIN 

		SELECT * FROM [#batched_operation_602436EA] ORDER BY [is_error], [detail_id];

		RAISERROR(N'Errors occurred during cleanup.', 16, 1);

	END;

	RETURN 0;
GO