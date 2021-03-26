/*
 *	Data Extraction from triax Database
 *
 */


/******************************************************************************************************
 ******************************************************************************************************
 *	Question 1, Billale Hours
 */

/* Query to get daily billable hours per worker_id
 * 
 * Someone apparently lives on site and spends a few minutes offsite? This gives a negative
 * value and later we will filter out negatives and igore them, flagging them for investigation
 * later.
 *
 *   id   |     time_stamp      | site_id | worker_id | activity | reason | success_yn
 * -------+---------------------+---------+-----------+----------+--------+------------
 *  12725 | 2019-08-12 19:44:16 |     217 |     45651 | enter    |        |          1
 *  12724 | 2019-08-12 19:44:02 |     217 |     45651 | exit     |        |          1
 * 
 * 	This worker appears to use gates without an iot:
 *
 * 		SELECT * 
 * 			FROM gate_transactions 
 * 			WHERE worker_id = 45651 
 * 			ORDER BY time_stamp;
 */
CREATE TEMPORARY TABLE dba_tmp AS
	SELECT
		MAX(wp.subcontractor_id) AS subcontractor_id,
		gt.worker_id AS worker_id,
		DATE(gt.time_stamp) AS date_worked,
		TO_CHAR(DATE(gt.time_stamp), 'IWYYYY') AS year_week,
		EXTRACT(EPOCH FROM MAX(gt_out.time_stamp)) AS last_out,
		EXTRACT(EPOCH FROM MIN(gt_in.time_stamp)) AS first_in, 
		SUM(CASE WHEN gt.activity = 'exit' THEN 1 ELSE 0 END) AS num_out,
		SUM(CASE WHEN gt.activity = 'enter' THEN 1 ELSE 0 END) AS num_in,
		CAST(
			(EXTRACT(EPOCH FROM MAX(gt_out.time_stamp))
				- EXTRACT(EPOCH FROM MIN(gt_in.time_stamp))
			) / 3600.0 AS DECIMAL(20, 2)) AS hours_worked
	FROM gate_transactions gt
	LEFT JOIN (SELECT worker_id, time_stamp FROM gate_transactions WHERE activity = 'exit') gt_out
		ON
			gt_out.worker_id = gt.worker_id
			AND DATE(gt_out.time_stamp) = DATE(gt.time_stamp)
	LEFT JOIN (SELECT worker_id, time_stamp FROM gate_transactions WHERE activity = 'enter') gt_in
		ON 
			gt.worker_id = gt_in.worker_id 
			AND DATE(gt_in.time_stamp) = DATE(gt.time_stamp)
	LEFT JOIN worker_profiles wp
		ON
			wp.id = gt.worker_id
	WHERE
		wp.subcontractor_id IS NOT NULL
	GROUP BY
		gt.worker_id,
		DATE(gt.time_stamp)
	ORDER BY 
		gt.worker_id,
		DATE(gt.time_stamp)
; -- End dba_tmp
\COPY (SELECT * FROM dba_tmp) TO 'main_tmp.csv' CSV HEADER;

/*
 * Export data as CSV:
 *
 *  subcontractor_id | monday_date | billable_hours
 * ------------------+-------------+----------------
 *              2113 | 2018-12-31  |         446.12
 *               100 | 2018-12-31  |          76.80
 * ...
 */
CREATE TEMPORARY TABLE tmp_out AS 
	SELECT
		wp.subcontractor_id AS subcontractor_id,
		TO_DATE(dt.year_week, 'IWYYYY') AS monday_date,
		SUM(dt.hours_worked) AS billable_hours
	FROM dba_tmp dt
	LEFT JOIN worker_profiles wp ON wp.id = dt.worker_id
	WHERE
		dt.hours_worked > 0.0
		AND wp.subcontractor_id IS NOT NULL
	GROUP BY
		wp.subcontractor_id,
		dt.year_week
	ORDER BY
		monday_date, subcontractor_id
; -- End of tmp table for export
\COPY (SELECT * FROM tmp_out) TO 'D1_weekly_billable_hours.csv' CSV HEADER;
DROP TABLE tmp_out;

/******************************************************************************************************
 ******************************************************************************************************
 *	Question 2, Workers Provided by Subcontractor
 */

/*
 *	Check which of the workers have shown up to the site at least once.
 */
CREATE TEMPORARY TABLE have_worked_tmp AS
	SELECT
		DISTINCT worker_id 
	FROM dba_tmp;

/*
 * Export Data as CSV:
 *
 *  subcontractor_id | percent_working | workers_arrived | workers_promised
 * ------------------+-----------------+-----------------+------------------
 *              4032 | 0.00%           |              0  |                6
 *               636 | 0.00%           |              0  |                6
 */
CREATE TEMPORARY TABLE tmp_out AS 
	SELECT
		sub_totals.subcontractor_id AS subcontractor_id,
		CAST(
				COALESCE(sub_worked.nworkers, 0.0) / sub_totals.nworkers
				AS DECIMAL(20, 2)
				) AS fraction_working,
		CONCAT(CAST(
					100.0 * COALESCE(sub_worked.nworkers, 0.0) / sub_totals.nworkers
					AS DECIMAL(20, 2)
					), '%') AS percent_working,
		COALESCE(sub_worked.nworkers, 0) AS workers_arrived,
		sub_totals.nworkers AS workers_promised
	FROM (
			SELECT 
				subcontractor_id,
				COUNT(id) AS nworkers 
			FROM worker_profiles
			GROUP BY subcontractor_id
			) sub_totals
	LEFT JOIN (
				SELECT
					subcontractor_id,
					COUNT(id) AS nworkers
				FROM worker_profiles
				WHERE id IN (SELECT * FROM have_worked_tmp)
				GROUP BY subcontractor_id
				) sub_worked
		ON sub_totals.subcontractor_id = sub_worked.subcontractor_id
	ORDER BY fraction_working
;
\COPY (SELECT * FROM tmp_out) TO 'D2_percent_workers_sent_to_site.csv' CSV HEADER;
DROP TABLE tmp_out;


/******************************************************************************************************
 ******************************************************************************************************
 *	Question 3, Daily Headcount
 */


CREATE TEMPORARY TABLE tmp_out AS 
	SELECT
		tbl.date_worked,
		COUNT(tbl.worker_id)
	FROM (SELECT DISTINCT date_worked, worker_id FROM dba_tmp) tbl
	GROUP BY tbl.date_worked
	ORDER BY tbl.date_worked DESC
;
\COPY (SELECT * FROM tmp_out) TO 'D3_daily_heacount_on_jobsite.csv' CSV HEADER;
DROP TABLE tmp_out;




/******************************************************************************************************
 ******************************************************************************************************
 *	Question 4, Site Security
 */
CREATE TEMPORARY TABLE tmp_out AS
	SELECT
		DISTINCT dt.subcontractor_id,
		dt.worker_id
	FROM dba_tmp dt
	WHERE
		dt.num_in != num_out
		OR hours_worked < 0.0
	ORDER BY dt.subcontractor_id, dt.worker_id
;
\COPY (SELECT * FROM tmp_out) TO 'D4a_security_risks.csv' CSV HEADER;
DROP TABLE tmp_out;


CREATE TEMPORARY TABLE iot_work_hours AS
	SELECT
		iot_tmp.worker_id,
		iot_tmp.date_worked,
		SUM(iot_tmp.hours_worked) AS hours_worked
	FROM (SELECT 
			os_iot.worker_id,
			MAX(DATE(os_iot.in_timestamp)) AS date_worked,
			CAST(
				(EXTRACT(EPOCH FROM MAX(os_iot.out_timestamp))
					- EXTRACT(EPOCH FROM MIN(os_iot.in_timestamp))
				) / 3600.0 AS DECIMAL(20, 2)) AS hours_worked
			FROM on_site_iot_session os_iot
			GROUP BY os_iot.worker_id, DATE(os_iot.in_timestamp)) iot_tmp
	GROUP BY
		iot_tmp.worker_id, iot_tmp.date_worked
;

CREATE TEMPORARY TABLE tmp_out AS
	SELECT
		wp.subcontractor_id,
		TO_DATE(dt.year_week, 'IWIYYYY') AS monday_date,
		SUM(CAST(CASE
			WHEN iwh.hours_worked IS NULL -- Either is null, use the other or zero.
				OR dt.hours_worked IS NULL
				OR iwh.hours_worked = 0.0 -- Division by zero when comparing sizes
				THEN COALESCE(dt.hours_worked, iwh.hours_worked, 0.0)
					-- When gate hours < 0 and iwh hours 0 should not happen...
			WHEN dt.num_in != dt.num_out -- umatched in/outs or dramatically (5%) difference
				OR ABS(dt.hours_worked - iwh.hours_worked) / iwh.hours_worked > 0.05
				THEN iwh.hours_worked
			ELSE -- Default is to use the gate value info
				dt.hours_worked
			END 
			AS DECIMAL(20, 2))) AS billable_hours
	FROM dba_tmp dt
	LEFT JOIN iot_work_hours iwh
		ON
			iwh.worker_id = dt.worker_id
			AND iwh.date_worked = dt.date_worked
	LEFT JOIN worker_profiles wp 
		ON
			wp.id = dt.worker_id
	WHERE
		wp.subcontractor_id IS NOT NULL
	GROUP BY wp.subcontractor_id, dt.year_week
	ORDER BY monday_date, wp.subcontractor_id
; 
\COPY (SELECT * FROM tmp_out) TO 'D4b_improved_billable_hours.csv' CSV HEADER;
DROP TABLE tmp_out;
