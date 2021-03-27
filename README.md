Tracking Jobsite Workers
==================================


### Database Setup: db\_schema.sql

After setting the '/path/to/date/folder/' string on line 20 of the
script, run the commands as
	postgres -d <database_name> -f db\_schema.sql

### Data Extraction: data\_exraction.sql

This script will export the data required for each of the deliverables as csv
files, each one prefixed by 'DXX\_' where XX is the delivarable number.

All the SQL to create the data are in the script. A few notes on the individual
queries and deliverables are below.

#### 1, Billable Hours via Gate Transactions

The initial billable hours estimate doesn't take mismatched in/outs into account,
just uses the earliest in and latest out. It does filter on negative hours worked,
and discards these hours to not reduce the total billable hours.

The week is defined as Monday, so March 22, 2021 would include 
March 22 - March 28, 2021.

The dashboard would show total billable hours per week, per contractor\_id.

#### 2, Workers Provided by Contractor

The contractors that have not sent a single worker to date are those contractors
who have sent 0% of the workers they registered in our system (worker\_profiles.csv).

The data displays contractor\_id and percent of workers registered who have checked in
at least once to the jobsite via the gate transactions. The data is sorted by percent,
ascending.

The dashboard would show the contractor\_id and percent of workers sent onsite to date.

#### 3, Daily Headcount

This uses the gate transaction data to check how many workers go to the site, per
contractor per day. 

The dashboard would show a collapsible row by day with the total headcount for the
day. When the row is expanded, the head count for each contractor is displayed.

#### 4, Security Risks and Updated Billable Hours Estimate

##### Security Risk 

The first part lists each worker id that has mismatched in/outs (totals of each
for the day are not equal), or had negative hours for the day. The dashboard is 
again collapsible rows, one for each contractor showing the total number of workers
that pose security risks. Expanding the row shows each worker that posed a security
risk.

##### Updated Billable Hours Estimate

The first step was to turn the iot session data into hours, which was done by
summing the session lengths (OUT - IN per record) per worker per day.

The next was to compare the IoT session data to the gate transaction data, and we
used a 5% difference to mean "dramatically" different. To calculate the percent difference
we took:
		100.0 * | gate_time - iot_time | / iot_time

We used a FULL OUT JOIN to make sure we got all worked hours between the IoT data and
the gate transaction data. Using that outer join table, we took the "more accurate"
hours worked for the day.

"More accurate" was defined as:
	1. If either data was NULL, or IoT data was zero, we COALESCEd the hours worked.
	2. If the in/outs on the gate transaction data was mismatched, or the gate and IoT
		data disagreed by more than 5%, we used the IoT hours worked.
	3. Finally, for all other cases we used the gate transaction hours worked data.

The dashboard is identical to the one for the initial Billable Hours task, but with
the updated data.
### Dashboards: \*.png

Using the data exported from the SQL above, I laid out some example dashboards of what
I'd present to the customer. They're pretty rough, just colored tables from LibreOffice.

If this was my first day on the job, I'd bring the data and these sketches to you or
another analyst, and ask how to quickly plug into the AWS dashboard Triax uses. At my 
current job, I'd use the queries to pull out the data via PHP PDO and display it on a
webpage. 
