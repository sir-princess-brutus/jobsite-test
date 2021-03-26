/*
 *	Table Schema for Analyst Take-home Exercise
 *
 *	Notes:
 *		- TEXT: I chose TEXT datatypes rather than VARCHAR(N) or CHAR(N) ro account for
 *			any lengths of data. Likely in production we'd have a good idea of what values are
 *			allowed, so could define N and have it in documentation.
 *		- Add additional indexes on other ids.
 *		- Add foreign key checks or site and worker ids. 
 *			* ERROR: 
 *				insert or update on table "gate_transactions" violates foreign key constraint "fk_worker_id"
 *				DETAIL:  Key (worker_id)=(19629) is not present in table "worker_profiles".
 *			* Disbabled foreign key check for gate_transaction data copy.
 */



CREATE DATABASE triax;
\c triax;
\cd '/path/to/data/folder/'; 

-- Worker profile table, worker_id is a foreign key in later tables.
CREATE TABLE worker_profiles
(
	id BIGINT PRIMARY KEY,
	subcontractor_id BIGINT
);
CREATE INDEX subcontractor_id_wp ON worker_profiles (subcontractor_id);
\COPY worker_profiles FROM 'worker_profiles.csv' DELIMITER ',' CSV HEADER;


-- Sites table, site_id is a foreign key in later tables.
CREATE TABLE sites
(
	id BIGINT PRIMARY KEY,
	company_id BIGINT,
	timezone TEXT
);
CREATE INDEX company_id_s ON sites (company_id);
\COPY sites FROM 'sites.csv' DELIMITER ',' CSV HEADER;


CREATE TABLE gate_transactions
(
	id BIGINT PRIMARY KEY,
	time_stamp TIMESTAMP,
	site_id BIGINT,
	worker_id BIGINT,
	activity TEXT,
	reason TEXT,
	success_yn SMALLINT,
	CONSTRAINT fk_site_id
		FOREIGN KEY(site_id)
		REFERENCES sites(id),
	CONSTRAINT fk_worker_id
		FOREIGN KEY(worker_id)
		REFERENCES worker_profiles(id)
);
CREATE INDEX site_id_gt ON gate_transactions (site_id);
CREATE INDEX worker_id_gt ON gate_transactions (worker_id);
ALTER TABLE gate_transactions DISABLE TRIGGER ALL;
\COPY gate_transactions FROM 'gate_transactions.csv' DELIMITER ',' CSV NULL AS 'NULL' HEADER;
ALTER TABLE gate_transactions ENABLE TRIGGER ALL;

CREATE TABLE on_site_iot_session
(
	id BIGINT PRIMARY KEY,
	in_timestamp TIMESTAMP,
	out_timestamp TIMESTAMP,
	site_id BIGINT,
	worker_id BIGINT,
	CONSTRAINT fk_site_id
		FOREIGN KEY(site_id)
		REFERENCES sites(id),
	CONSTRAINT fk_worker_id
		FOREIGN KEY(worker_id)
		REFERENCES worker_profiles(id)
);
CREATE INDEX site_id_os_iot_s ON on_site_iot_session (site_id);
CREATE INDEX worker_id_os_iot_s ON on_site_iot_session (worker_id);
\COPY on_site_iot_session FROM 'on_site_iot_session.csv' DELIMITER ',' CSV HEADER NULL AS 'NULL';


CREATE TABLE registered_workers
(
	id BIGINT PRIMARY KEY,
	site_id BIGINT,
	worker_id BIGINT,
	CONSTRAINT fk_site_id
		FOREIGN KEY(site_id)
		REFERENCES sites(id),
	CONSTRAINT fk_worker_id
		FOREIGN KEY(worker_id)
		REFERENCES worker_profiles(id)
);
CREATE INDEX site_id_rw ON  registered_workers (site_id);
CREATE INDEX worker_id_rw ON  registered_workers (worker_id);
\COPY registered_workers FROM 'registered_workers.csv' DELIMITER ',' CSV HEADER;
