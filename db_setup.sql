-- create monthly tables for .csv
create table bb_2020_12 (
starttime timestamp,
	endtime timestamp,
	druation bigint,
	startstation_id text,
	startstation_name text,
	startstation_description text,
	start_lat numeric,
	start_long numeric,
	endstation_id text,
	endstation_name text,
	endstation_description text,
	end_lat numeric,
	end_long numeric
);

-- import .csv in UTF8 encoding for each table

-- combine months into year view
create view bb_2020_view as(
SELECT * FROM bb_2020_01
	UNION ALL
SELECT * FROM bb_2020_02
	UNION ALL
SELECT * FROM bb_2020_03
	UNION ALL
SELECT * FROM bb_2020_04
	UNION ALL
SELECT * FROM bb_2020_05
	UNION ALL
SELECT * FROM bb_2020_06
	UNION ALL
SELECT * FROM bb_2020_07
	UNION ALL
SELECT * FROM bb_2020_08
	UNION ALL
SELECT * FROM bb_2020_09
	UNION ALL
SELECT * FROM bb_2020_10
	UNION ALL
SELECT * FROM bb_2020_11
	UNION ALL
SELECT * FROM bb_2020_12
);

--check view for all months
SELECT date_part('month',starttime), count(starttime)
FROM bb_2020_view
GROUP BY 1
ORDER BY 1;

-- create year tables table from view
create table bb_2020 AS (
SELECT * FROM bb_2020_view
);

--check year table for all months
SELECT date_part('month',starttime), count(starttime)
FROM bb_2020
GROUP BY 1
ORDER BY 1;

-- delete individual months
drop table if exists
	bb_2020_01, 
	bb_2020_02,
	bb_2020_03,
	bb_2020_04,
	bb_2020_05,
	bb_2020_06,
	bb_2020_07,
	bb_2020_08,
	bb_2020_09,
	bb_2020_10,
	bb_2020_11,
	bb_2020_12
	cascade;
	

-- combine years into multi-year view 
create view bb_all_trips as(
SELECT * FROM bb_2018
	UNION ALL
SELECT * FROM bb_2019
	UNION ALL
SELECT * FROM bb_2020
	UNION ALL
SELECT * FROM bb_2021
	UNION ALL
SELECT * FROM bb_2022
);

-- check view for all years
SELECT date_part('year', starttime), count(starttime)
FROM bb_all_trips
GROUP BY 1
ORDER BY 1;

-- create multi-year table from view
create table bb_all AS (
SELECT * FROM bb_all_trips
);

-- check table for all years
SELECT date_part('year', starttime), count(starttime)
FROM bb_all
GROUP BY 1
ORDER BY 1;

-- Create view showing a summary of station history based on start station information
create view end_station_summary_view AS (
SELECT 
	endstation_id,
	endstation_name,
	endstation_description,
	end_lat, 
	end_long, 
	min(endtime), 
	max(endtime),
	count(endtime)
FROM bb_all
GROUP BY endstation_id, endstation_id,
	endstation_name,
	endstation_description,
	end_lat, 
	end_long 
ORDER BY 1, 5
);

-- create start/end station summary table based on view
create table end_station_summary AS (
SELECT * FROM end_station_summary_view
);

-- rank start stations in number of all time trip starts (ignore location change)
SELECT station_id, sum(count)
FROM start_station_summary
GROUP BY station_id
ORDER BY sum(count) desc

-- rank end stations in number of all time trip ends (ignore location change)
SELECT endstation_id, sum(count)
FROM end_station_summary
GROUP BY station_id
ORDER BY sum(count) desc

-- create station reference table for data imported from JSON
create table station_info (
	station_id text,
	station_name text,
	lat numeric,
	long numeric,
	capacity int,
	elevation numeric
);

-- check station_info table
SELECT * FROM station_info;

-- assume latlongs are the same as most current lat long listings. use station_info to pull lat long

-- CLEANING
-- update main table to have start elevations and exclude records with no matching station ID
-- 3,100,342 records updated (33,864 records removed)
create view bb_all_start_elevation AS (
SELECT a.starttime, 
	a.endtime, 
	a.startstation_id, 
	a.startstation_name,
	a.start_lat,
	a.start_long,
	s.elevation start_elevation,
	a.endstation_id,
	a.endstation_name,
	a.endstation_description,
	a.end_lat,
	a.end_long
FROM bb_all a
JOIN station_info s ON a.startstation_id = s.station_id
);

-- check bb_all_start_elevation view
SELECT * FROM bb_all_start_elevation LIMIT 100;

-- create table with end elevations added and exclude records with no matching station ID
-- 3,072,028 records updated (23,314 records removed)
-- 62,178 rows less than original
create table bb_all_02 AS(
SELECT a.starttime, 
	a.endtime, 
	a.startstation_id, 
	a.startstation_name,
	a.start_lat,
	a.start_long,
	a.start_elevation,
	a.endstation_id,
	a.endstation_name,
	a.endstation_description,
	a.end_lat,
	a.end_long,
	s.elevation end_elevation
FROM bb_all_start_elevation a
JOIN station_info s ON a.endstation_id = s.station_id
);

-- add elevation_change col to bb_all_02
ALTER TABLE bb_all_02
ADD elevation_change int;

-- check bb_all_02
SELECT * FROM bb_all_02 LIMIT 100;

-- fill elevation_change col 
UPDATE bb_all_02
SET elevation_change = end_elevation-start_elevation;

-- check for duplicate trips
-- 3120 records returned
create view duplicate_trips_01 AS (
SELECT starttime, 
	endtime, 
	startstation_id, 
	startstation_name, 
	endstation_id, 
	endstation_name, 
	count(starttime) countstart
FROM bb_all_02
GROUP BY 1,2,3,4,5,6
HAVING count(starttime) >1
ORDER BY count(starttime) desc
);

-- create view without duplicates
-- 3,064,780 (7,248 duplicates removed)
create view bb_all_03 AS(
SELECT *
FROM(
SELECT *,
	ROW_NUMBER() OVER (PARTITION BY 
			starttime,
			endtime,
			startstation_id,
			endstation_id
		ORDER BY
			startstation_id) 
			AS rank
FROM bb_all_02
) AS t1
WHERE rank = 1
);

-- check view for duplicates
-- 0 records returned
SELECT starttime, 
	endtime, 
	startstation_id, 
	startstation_name, 
	endstation_id, 
	endstation_name, 
	count(starttime) countstart
FROM bb_all_03
GROUP BY 1,2,3,4,5,6
HAVING count(starttime) >1
ORDER BY count(starttime) desc
;

-- create bb_all_03 with no duplicates
create table bb_all_03t AS(
SELECT * FROM bb_all_03
);

-- delete view, rename table to bb_all_03

-- check for nulls in starttime, endtime, and start and end ids
-- 0 records returned
SELECT *
FROM bb_all_03
WHERE starttime IS NULL
OR endtime IS NULL
OR startstation_ID IS NULL
OR endstation_ID IS NULL
OR startstation_name IS NULL
OR endstation_name IS NULL

-- check start times are before end times
-- all intervals are positive
SELECT starttime, endtime, endtime-starttime as duration
FROM bb_all_03
ORDER BY duration asc;

-- average trip time before cleaning
-- "00:10:41.388439"
SELECT avg(endtime-starttime)
FROM bb_all_03

-- check for trips that are less than 90 seconds
-- 28,865 trips returned
SELECT * 
FROM bb_all_03
WHERE endtime-starttime < '00:01:30.000';

-- check for multiday trips
-- 148 trips returned
SELECT * 
FROM bb_all_03
WHERE endtime-starttime > '24:00:00.000'

-- create bb_all_04 with trips shorter than 90s and multiday trips removed
-- 3,035,767 trips returned (29,013 trips fewer)
create view bb_all_04v AS (
SELECT * 
FROM bb_all_03
WHERE endtime-starttime <= '24:00:00.000'
AND endtime-starttime >= '00:01:30.000'
);

create table bb_all_04 AS (
SELECT *
FROM bb_all_04v
);

-- DATA PROFILE ------------------------------------------------

-- how many trips total were there BEFORE cleaning? 
-- 3,134,206
SELECT count(*)
FROM bb_all;

-- how many trips total were there AFTER cleaning? 
-- 3,035,767 (~97% of original data)
SELECT count(*)
FROM bb_all_04;

-- how many trips started and ended at the same location BEFORE cleaning? 
-- 93,221 (about 3% of bike rides)
SELECT startstation_id station_id
FROM bb_all
WHERE startstation_id=endstation_id;

-- how many trips started and ended at the same location AFTER cleaning? 
-- 71,505 (about 3% of bike rides)
SELECT startstation_id station_id
FROM bb_all_04
WHERE startstation_id=endstation_id;

-- Stations ranked by elevation
SELECT station_name, elevation
FROM station_info
ORDER BY elevation desc;

-- max elevation
-- 55 meters
SELECT max(elevation)
FROM station_info;

-- min elevation
-- 0 meters
SELECT min(elevation)
FROM station_info;

-- average elevation
-- 16.6 meters
SELECT avg(elevation)
FROM station_info;

-- mode elevation
-- 20 meters (15 stations)
-- 19 meters (14 stations)
SELECT elevation, count(elevation)
FROM station_info
GROUP BY elevation
ORDER BY count(elevation) desc;

-- median elevation (need elevation rank)
-- 17 meteres
SELECT elevation, rank
FROM(
	SELECT elevation,
		RANK() OVER (ORDER BY elevation) AS rank
	FROM station_info
) AS t1
WHERE rank = 105/2;

-- add elevation level to station info 
create view station_info_v AS(
SELECT *,
 CASE
	WHEN elevation < 11 THEN '1'
	WHEN elevation < 22 THEN '2'
	WHEN elevation < 33 THEN '3'
	WHEN elevation < 44 THEN '4'
	ELSE '5' END AS elevation_level
FROM station_info
);

-- create table from view
create table station_info_t AS(
SELECT * FROM station_info_02
);

-- count stations at each elevation level
SELECT elevation_level, count(*) num_stations
FROM station_info_02
GROUP BY elevation_level
ORDER BY count(*) desc;

-- count number of stations and rides starting at each level
SELECT elevation_level, 
	count(*) num_trip_starts
FROM bb_all_04 r
JOIN station_info_02 s ON r.startstation_id = s.station_id
GROUP BY elevation_level
ORDER BY count(*) desc;

-- count number of stations and rides ending at each level
SELECT elevation_level, 
	count(*) num_trip_ends
FROM bb_all_04 r
JOIN station_info_02 s ON r.endstation_id = s.station_id
GROUP BY elevation_level
ORDER BY count(*) desc;

-- average trip elevation change
-- -0.5 meters
SELECT avg(elevation_change)
FROM bb_all_04;

-- max trip elevation change
-- 55 meters
SELECT max(elevation_change)
FROM bb_all_04;

-- min trip elevation change
-- -55 meters
SELECT min(elevation_change)
FROM bb_all_04;

-- average trip elevation change when starting in level 5
-- -34.9 meters
SELECT avg(elevation_change)
FROM bb_all_04
WHERE start_elevation > 44;

-- average trip elevation change when ending in level 5
-- -33.7 meters
SELECT avg(elevation_change)
FROM bb_all_04
WHERE end_elevation > 44;

-- average trip elevation change when starting in level 1
-- 8.5 meters
SELECT avg(elevation_change)
FROM bb_all_04
WHERE start_elevation < 11;

-- average trip elevation change when ending in level 0
-- -8.5 meters
SELECT avg(elevation_change)
FROM bb_all_04
WHERE end_elevation < 11;

-- top ten start stations by trip count (include elevation)
	-- "220"	"Møllendalsplass"		116904	20
	-- "368"	"Festplassen"			104211	 7
	-- "157"	"Florida Bybanestopp"	 90863	20
	-- "814"	"Nykirken"				 87254	 2
	-- "794"	"St. Jakobs Plass"		 71557	16
	-- "150"	"Torget"				 67163	 4
	-- "1045"	"Damsgårdsveien 2"		 59871	19
	-- "34"		"Cornerteateret"		 59072	18
	-- "819"	"Thormøhlens gate"		 58999	18
	-- "641"	"Krohnviken"			 57544	18
SELECT r.startstation_id startstation_id, 
	s.station_name startstation_name, 
	count(*) num_trip_starts,
	s.elevation
FROM bb_all_04 r
JOIN station_info_02 s ON r.startstation_id = s.station_id
GROUP BY r.startstation_id, s.station_name, s.elevation
ORDER BY num_trip_starts desc
LIMIT 10;

-- top ten end stations by trip count
	-- "220"	"Møllendalsplass"	116804	20
	-- "368"	"Festplassen"	110863	7
	-- "157"	"Florida Bybanestopp"	100000	20
	-- "814"	"Nykirken"	87058	2
	-- "794"	"St. Jakobs Plass"	73401	16
	-- "150"	"Torget"	67325	4
	-- "34"	"Cornerteateret"	61664	18
	-- "819"	"Thormøhlens gate"	59788	18
	-- "1045"	"Damsgårdsveien 2"	59150	19
	-- "641"	"Krohnviken"	58731	18
SELECT r.endstation_id endstation_id, 
	s.station_name endstation_name, 
	count(*) num_trip_starts,
	s.elevation
FROM bb_all_04 r
JOIN station_info_02 s ON r.endstation_id = s.station_id
GROUP BY r.endstation_id, s.station_name, s.elevation
ORDER BY num_trip_starts desc
LIMIT 10;

-- bottom ten start stations by count
	-- "2321"	"Damsgårdsveien 125"	466	0
	-- "2338"	"Bontelabo"	555	0
	-- "2314"	"Kalfarveien 31"	663	40
	-- "2346"	"Gamle Bergen"	736	21
	-- "1896"	"Takhagen på Nordnes"	2954	4
	-- "1898"	"Kronstad"	3383	37
	-- "2336"	"Møllestranden"	3434	19
	-- "798"	"H.M. Pinnsvinet"	3982	19
	-- "1897"	"NHH"	4199	47
	-- "1889"	"Nordnes Sjøbad"	4319	1
SELECT r.startstation_id startstation_id, 
	s.station_name startstation_name, 
	count(*) num_trip_starts,
	s.elevation
FROM bb_all_04 r
JOIN station_info_02 s ON r.startstation_id = s.station_id
GROUP BY r.startstation_id, s.station_name, s.elevation
ORDER BY num_trip_starts asc
LIMIT 10;

-- bottom ten end stations by count
	-- "2321"	"Damsgårdsveien 125"	470	0
	-- "2338"	"Bontelabo"	549	0
	-- "2314"	"Kalfarveien 31"	641	40
	-- "2346"	"Gamle Bergen"	653	21
	-- "798"	"H.M. Pinnsvinet"	2269	19
	-- "1896"	"Takhagen på Nordnes"	2946	4
	-- "1898"	"Kronstad"	3148	37
	-- "2336"	"Møllestranden"	3484	19
	-- "1897"	"NHH"	3719	47
	-- "367"	"Haraldsplass"	4081	41
SELECT r.endstation_id endstation_id, 
	s.station_name endstation_name, 
	count(*) num_trip_starts,
	s.elevation
FROM bb_all_04 r
JOIN station_info_02 s ON r.endstation_id = s.station_id
GROUP BY r.endstation_id, s.station_name, s.elevation
ORDER BY num_trip_starts asc
LIMIT 10;

-- number of routes taken 10758
	-- "789"	"220"	10449
	-- "220"	"789"	8104
	-- "215"	"220"	8011
	-- "220"	"215"	7849
	-- "220"	"368"	7493
	-- "220"	"157"	7070
	-- "157"	"220"	6611
	-- "24"		"157"	6600
	-- "794"	"368"	6435
	-- "58"		"814"	6427
SELECT startstation_id, endstation_id, count(*) trip_count
FROM bb_all_04
GROUP BY 1, 2
ORDER BY trip_count desc;

-- bottom ten routes by count
	-- 186 routes with 1 trip
SELECT startstation_id, endstation_id, count(*) trip_count
FROM bb_all_04
GROUP BY 1, 2
ORDER BY trip_count asc;

-- create route table
create table route_popularity_01 AS (
SELECT startstation_id, endstation_id, count(*) trip_count
FROM bb_all_04
GROUP BY 1, 2
ORDER BY trip_count desc
);

-- largest ratio of trip start count to trip end count
	-- create station popularity by count
WITH popular_start_stations AS(
	SELECT r.startstation_id station_id, 
		s.station_name station_name, 
		count(*) num_trip_starts
	FROM bb_all_04 r
	JOIN station_info_02 s ON r.startstation_id = s.station_id
	GROUP BY r.startstation_id, s.station_name
),
popular_end_stations AS(
	SELECT r.endstation_id station_id, 
		s.station_name station_name, 
		count(*) num_trip_ends
	FROM bb_all_04 r
	JOIN station_info_02 s ON r.endstation_id = s.station_id
	GROUP BY r.endstation_id, s.station_name
),
combined_stations AS(
	SELECT s.station_id, 
	s.station_name, 
	s.num_trip_starts, 
	e.num_trip_ends
	FROM popular_start_stations s
	JOIN popular_end_stations e USING(station_id)
)
	SELECT station_id,
		station_name, 
		num_trip_starts, 
		num_trip_ends,
		num_trip_starts - num_trip_ends difference
	FROM combined_stations
	ORDER BY ABS(num_trip_starts - num_trip_ends) desc;

-- top ten start stations by avg daily start rate (all time) count
	-- divide count by days_present to get daily_trip_start_rate
SELECT startstation_id, 
	ROUND(count/days_present::numeric,1) daily_trip_start_rate
	FROM (
		-- compute days_present
		SELECT startstation_id, count, 
			date_part('day',max-min) days_present
		FROM (
			-- get max and min times
			SELECT startstation_id, 
				count(startstation_id) count, 
				min(starttime), 
				max(starttime)
			FROM bb_all_04 r
			GROUP BY startstation_id
		) t1
	ORDER BY days_present
	) t2
ORDER BY daily_trip_start_rate desc;


-- top ten end stations by end rate
	-- divide count by days_present to get daily_trip_end_rate
SELECT endstation_id, 
	ROUND(count/days_present::numeric,1) daily_trip_end_rate
	FROM (
		-- compute days_present
		SELECT endstation_id, count, 
			date_part('day',max-min) days_present
		FROM (
			-- get max and min times
			SELECT endstation_id, 
				count(endstation_id) count, 
				min(endtime), 
				max(endtime)
			FROM bb_all_04 r
			GROUP BY endstation_id
		) t1
	ORDER BY days_present
	) t2
ORDER BY daily_trip_end_rate desc;

-- create view to add max/min start times/days in operation to station_info_02
create table station_info_03 AS (
	SELECT s.station_id,
		s.station_name,
		s.lat,
		s.long,
		s.capacity,
		s.elevation,
		s.elevation_level,
		t2.qty_starts,
		t2.earliest_trip,
		t2.last_trip,
		t2.num_days_operating
	FROM station_info_02 s
	JOIN (
		-- calculate number of days in opperation
		SELECT *, 
			last_trip-earliest_trip num_days_operating
		FROM(
			-- select max/min start times for each station
			SELECT startstation_id, 
				count(startstation_id) qty_starts, 
				min(starttime) earliest_trip, 
				max(starttime) last_trip
			FROM bb_all_04 r
			GROUP BY startstation_id
		) as t1 ) as t2
	ON s.station_id = t2.startstation_id
);

-- top ten routes by rate
create table route_popularity_02 AS (
	WITH start_ref AS (SELECT * FROM station_info_03
				),
		end_ref AS (SELECT * FROM station_info_03
				),
		route_ref AS (
			SELECT rp.*, 
				sr.num_days_operating AS start_num_days_operating, 
				er.num_days_operating AS end_num_days_operating
			FROM route_popularity_01 rp
			JOIN start_ref sr ON sr.station_id = rp.startstation_id
			JOIN end_ref er ON er.station_id = rp.endstation_id
				)
	SELECT startstation_id, endstation_id, trip_count, 
		CASE
			WHEN start_num_days_operating <= end_num_days_operating THEN trip_count/date_part('day', start_num_days_operating)
			ELSE trip_count/date_part('day', end_num_days_operating)
			END daily_trip_rate
	FROM route_ref
	ORDER BY daily_trip_rate desc
);

--
SELECT min(earliest_trip), max(last_trip)
FROM station_info_03;
-- "2018-06-29 10:45:12.736"	"2022-08-31 21:53:39.188"


-- generate series of days
-- https://stackoverflow.com/questions/14113469/generating-time-series-between-two-dates-in-postgresql

-- create hourly usage table
create table hourly_usage_01 AS (
	SELECT t.hour
	FROM   generate_series(timestamp '2018-06-29' 
						 , timestamp '2022-08-31'
						 , interval  '1 hour') AS t(hour)
);

-- add tablefunc module
-- https://blog.devart.com/pivot-tables-in-postgresql.html
CREATE EXTENSION IF NOT EXISTS tablefunc;


-- hourly count of trip starts from each station (- bike from station)
-- 1103614 rows
create table hourly_starts AS(
	SELECT  
		date_trunc('hour',starttime) trip_hour,
		startstation_id station_id,
		count(starttime) bikes_removed
	FROM bb_all_04
	GROUP BY 2, 1
	ORDER BY 1, startstation_id::numeric
);


-- list of station names in order
SELECT station_name FROM station_info ORDER BY 1 asc;

-- create table with hourly usage for each station, bikes added, bikes removed, and hourly change in bike availability
create table hourly_usage_02 AS (
	WITH
		-- list of all station ids
		station_id_list AS(
		SELECT station_id
		FROM station_info
		ORDER BY station_id::numeric
	),
		-- count of trip starts for each hour and station
		hourly_starts_by_station AS(
		SELECT  
			date_trunc('hour',starttime) trip_hour,
			startstation_id station_id,
			count(starttime) bikes_removed
		FROM bb_all_04
		GROUP BY 2, 1
	),
		-- count of trip ends for each hour and station
		hourly_ends_by_station AS(
		SELECT  
			date_trunc('hour',endtime) trip_hour,
			endstation_id station_id,
			count(endtime) bikes_added
		FROM bb_all_04
		GROUP BY 2, 1
	),
		-- all hours and all stations
		cartesian_product_hour_station AS(
		SELECT *
		FROM hourly_usage_01
		CROSS JOIN station_id_list
	),
		-- add bikes_removed and bikes_added to cartesian product
		station_hourly_usage AS (
		SELECT cphs.hour, 
			cphs.station_id, 
			CASE WHEN bikes_removed IS NULL THEN 0 ELSE bikes_removed END,
			CASE WHEN bikes_added IS NULL THEN 0 ELSE bikes_added END
		FROM cartesian_product_hour_station cphs
		LEFT JOIN hourly_starts_by_station hs
		ON cphs.hour = hs.trip_hour AND cphs.station_id = hs.station_id
		LEFT JOIN hourly_ends_by_station he
		ON cphs.hour = he.trip_hour AND cphs.station_id = he.station_id
	)
	-- add column showing change in bikes available
	SELECT *, bikes_added-bikes_removed hourly_change
	FROM station_hourly_usage
);

--create table showing only hours when bikes were added or removed 
create table hourly_usage_02_cond AS (
	SELECT *
	FROM hourly_usage_02
	WHERE bikes_added != 0 AND bikes_removed != 0
	ORDER BY 1, 2
)

-- compare capacity to hourly change
SELECT h.hour, h.station_id, h.hourly_change, s.capacity
FROM hourly_usage_02_cond h
JOIN station_info_03 s USING(station_id)
WHERE abs(h.hourly_change) > s.capacity

	
-- 
	
	
	-- hourly count of trips ending at each station (+1 bike at station)
	-- 1,093,726 rows
	ends AS (
	SELECT  
		date_trunc('hour',endtime), 
		endstation_id::numeric,
		count(endtime) bikes_added
	FROM bb_all_04
	GROUP BY 2, 1
	ORDER BY 1, 2
	)
SELECT hu.hour, e.endstation_id, start_count, end_count
FROM hourly_usage_01 hu
LEFT JOIN starts s ON hu.hour = s.date_trunc
LEFT JOIN ends e ON hu.hour = e.date_trunc
GROUP BY 1, 2
ORDER BY hu.hour;

create table bike_route_map (
	route text,
	distance numeric,
	latitude numeric,
	longitude numeric,
	point_order bigint
);

create table truck_route_map (
	delete_me int,
	route text,
	distance numeric,
	latitude numeric,
	longitude numeric,
	point_order bigint
);

create table route_popularity_03 AS (
	SELECT CONCAT(startstation_id, ' – ', endstation_id) route_id, *
	FROM route_popularity_02
	
)
SELECT dense_rank() OVER (ORDER BY )
FROM (
	SELECT 
		p.route, 
		p.daily_trip_rate, 
		t.distance, 
		p.startstation_id, 
		p.endstation_id, 
		t.latitude, 
		t.longitude, 
		t.point_order
	FROM truck_route_map t
	JOIN route_popularity_03 p USING(route)
)



