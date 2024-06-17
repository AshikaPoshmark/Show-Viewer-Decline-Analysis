
-- Problem statement : The daily show viewers in the month of January has reached 75k+, however starting February, the viewers began to decline, reaching over 70k+ by May. As a result, there is a significant drop in the weekly viewership from 300k+ to 280k+

-- Hypothesis 1 : The viewers coming from different traffic sources are declining, which in turn is affecting the shows viewership.
                    -- 1.1. Are both First time Viewers and Repeat Viewers Affected.


-------------------------------------------------------------------- First VS Repeat Unique Viewers --------------------------------------------------------------------


------- Calculate weekly viewer metrics, including new, repeat, and total show unique viewer

SELECT 
-- Calculate the show start week
      (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)),
        'YYYY-MM-DD'))                   AS show_start_week,

    -- Count new viewers for the week 
       COUNT(DISTINCT CASE
                          WHEN (DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_users_cs.show_viewer_activated_at)::integer),
                                             dw_users_cs.show_viewer_activated_at))) =
                               (DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer),
                                             dw_shows.start_at)))
                              THEN CASE
                                       WHEN show_viewer_events.viewer_id != show_viewer_events.host_id
                                           THEN show_viewer_events.viewer_id
                                       ELSE NULL END
                          ELSE NULL
           END)                          AS New_Viewers,
    -- Count repeat viewers for the week 
       COUNT(DISTINCT CASE
                          WHEN (DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_users_cs.show_viewer_activated_at)::integer),
                                             dw_users_cs.show_viewer_activated_at))) <
                               (DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer),
                                             dw_shows.start_at)))
                              THEN CASE
                                       WHEN show_viewer_events.viewer_id != show_viewer_events.host_id
                                           THEN show_viewer_events.viewer_id
                                       ELSE NULL END
                          ELSE NULL
           END)                          AS Repeat_Viewers,

    -- Count total unique viewers for the week
       Count(DISTINCT CASE
                          WHEN show_viewer_events.viewer_id != show_viewer_events.host_id
                              THEN show_viewer_events.viewer_id
                          ELSE NULL END) AS Total_show_Viewers
FROM analytics.dw_show_viewer_events_cs AS show_viewer_events
      -- Join with user tables And Show table to get viewer and show details
         LEFT JOIN analytics.dw_users ON show_viewer_events.viewer_id = dw_users.user_id
         LEFT Join analytics.dw_users_cs ON show_viewer_events.viewer_id = dw_users_cs.user_id
         LEFT JOIN analytics.dw_shows AS dw_shows ON show_viewer_events.show_id = dw_shows.show_id
      -- Filter events up to a specific date and by origin domain
WHERE DATE(dw_shows.start_at) <= '2024-06-01'
  AND origin_domain = 'us'
GROUP BY 1
ORDER BY 1 desc;


-------------------------------------------------------------------- New vs Repeat Viewers across each Traffic Source -----------------------------------------------------


-------  New vs Repeat Viewers - Daily (D1, >D1)

-- Calculate daily new (D1) vs repeat (>D1) viewers based on their activation date
SELECT show_view_sources.event_date,
       -- Determine the show source based on session start that is it's the first session of the day
       CASE
           WHEN session_start_at = daily_start_session_at OR daily_start_session_at IS NULL
                THEN f_pm_show_source(daily_session_source, daily_session_notification_feature, daily_routing_on_name,
                (DATE(show_start_at)), daily_routing_content_type)
       END  AS Show_Source,
       -- Classify viewers as D1 if their activation date is the same as the event date, otherwise classify as D2+
       CASE
           WHEN DATE(show_viewer_activated_at) = show_view_sources.event_date THEN 'D1'
           WHEN DATE(show_viewer_activated_at) < show_view_sources.event_date THEN 'D2+'
       END AS Viewers_type,
       -- Count unique viewers per day
       COUNT(DISTINCT show_view_sources.user_id) AS Unique_Viewers
    FROM analytics_scratch.show_view_sources
    -- Join to get the first session start time of each user per day
         LEFT JOIN (SELECT event_date,
                           user_id,
                           MIN(session_start_at) AS daily_start_session_at
                    FROM analytics_scratch.show_view_sources
                    GROUP BY 1, 2) AS daily_start_session_at_table
                    ON show_view_sources.event_date = daily_start_session_at_table.event_date AND
                    show_view_sources.user_id = daily_start_session_at_table.user_id
         LEFT JOIN analytics.dw_users ON show_view_sources.user_id = dw_users.user_id
    -- Filter for events up to a specific date and within the US domain
    WHERE (DATE(show_view_sources.event_date) <= '2024-06-01')
    AND origin_domain = 'us'
    AND home_domain = 'us'
    AND Show_Source IS NOT NULL
    GROUP BY 1, 2, 3
    ORDER BY 1 DESC, 2, 3;



------- Average number of repeat viewers per day for each week, segmented by show source


-- Calculate the average number of repeat viewers per day for each week, segmented by show source

SELECT event_start_week, 
       Show_Source, 
       sum(Repeat_Viewers)/count(DISTINCT event_date ) AS Daily_Avg_Repeat_Viewers -- Average repeat viewers per day
FROM (SELECT  (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM show_view_sources.event_date)::integer),
                             show_view_sources.event_date)), 'YYYY-MM-DD')) AS event_start_week, -- Calculate the start of the week
       show_view_sources.event_date,
       CASE
           WHEN session_start_at = daily_start_session_at or daily_start_session_at is null
               THEN
    CASE
        WHEN DATE(show_viewer_activated_at) < show_view_sources.event_date -- Condition for repeat viewers
               THEN f_pm_show_source(daily_session_source, daily_session_notification_feature, daily_routing_on_name,
                        (DATE(show_start_at)),
                        daily_routing_content_type) -- Determine the show source
        END
        END AS Show_Source,


    Count(DISTINCT show_view_sources.user_id) AS Repeat_Viewers -- Count of unique repeat viewers
FROM analytics_scratch.show_view_sources
    -- Join to get the first session start time of each user per day
         LEFT JOIN (SELECT event_date,
                           user_id,
                           min(session_start_at) as daily_start_session_at
                    FROM analytics_scratch.show_view_sources
                    GROUP BY 1, 2) AS daily_start_session_at_table
                   ON show_view_sources.event_date = daily_start_session_at_table.event_date AND
                      show_view_sources.user_id = daily_start_session_at_table.user_id
         LEFT JOIN analytics.dw_users ON show_view_sources.user_id = dw_users.user_id
WHERE (DATE(show_view_sources.event_date) <= '2024-06-01') -- Filter for events up to a specific date
  AND origin_domain = 'us' -- Filter for US origin domain
  AND home_domain = 'us' -- Filter for US home domain
AND Show_Source IS NOT NULL 
GROUP BY 1, 2,3
ORDER BY 1 DESC, 2, 3) as t GROUP BY 1,2 Order by 1 desc;

----------------------------------------------------------------------------------------------------------------------------------------------------------------

-- Hypothesis 2 : Viewers are dropping only from a particular host segment as a set of active hosts have reduced the frequency of hosting a show.
                -- 2.1. Is the viewers declining for a particular type of show?



-------------------------------------------------------------------- Viewers by Host Segment --------------------------------------------------------------------


-- Calculate viewers by host segment, including unique viewers, Total show viewers, count of show, count of hosts and average viewers per show and per host

SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
           coalesce(host_segments_gmv_start.host_segment_daily, 'Segment 1: No Sales') AS host_segment,
           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id ELSE NULL END) AS Total_unique_show_Viewers,
           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN CONCAT(show_viewer_events.viewer_id ,show_viewer_events.show_id) ELSE NULL END) AS Total_show_Viewers,
           Count(distinct dw_shows.show_id) AS count_shows,
           Count(distinct dw_shows.creator_id) AS count_hosts,
           Total_show_Viewers/count_shows AS Avg_Viewers_per_show,
           Total_show_Viewers/count_hosts AS Avg_Viewers_per_host
FROM analytics.dw_shows
          LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
          
            -- Join with host segments to classify hosts based on their sales
           LEFT JOIN analytics_scratch.l365d_host_segment AS host_segments_gmv_start
                                   ON dw_shows.creator_id = host_segments_gmv_start.host_id AND
                                   (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)),'YYYY-MM-DD')) > (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM host_segments_gmv_start.start_date)::integer),
                                   host_segments_gmv_start.start_date)), 'YYYY-MM-DD')) and (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer),
                                   dw_shows.start_at)), 'YYYY-MM-DD')) <= (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW
                                   FROM coalesce(host_segments_gmv_start.end_date, GETDATE()))::integer),
                                   coalesce(host_segments_gmv_start.end_date, GETDATE()))), 'YYYY-MM-DD'))
WHERE origin_domain ='us' AND DATE(dw_shows.start_at) <= '2024-06-01'
          GROUP BY 1,2 order by 1 desc,2;


-------------------------------------------------------------------- Viewers by Host Segment and Show Type weekly level --------------------------------------------------------------------


SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
           coalesce(host_segments_gmv_start.host_segment_daily, 'Segment 1: No Sales') AS host_segment,
           CASE
               WHEN dw_shows.type = 'silent' then 'Silent Show'
                ELSE 'Live Show'
                    END AS Show_type,

           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id ELSE NULL END) AS Total_unique_show_Viewers,
           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN CONCAT(show_viewer_events.viewer_id ,show_viewer_events.show_id) ELSE NULL END) AS Total_show_Viewers,
           Count(distinct dw_shows.show_id) AS count_shows,
           Count(distinct dw_shows.creator_id) AS count_hosts,
           Total_show_Viewers/count_shows AS Avg_Viewers_per_show ,
           Total_show_Viewers/count_hosts AS Avg_Viewers_per_host
FROM analytics.dw_shows
          LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
           LEFT JOIN analytics_scratch.l365d_host_segment AS host_segments_gmv_start
                                   ON dw_shows.creator_id = host_segments_gmv_start.host_id AND
                                   (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)),'YYYY-MM-DD')) > (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM host_segments_gmv_start.start_date)::integer),
                                   host_segments_gmv_start.start_date)), 'YYYY-MM-DD')) and (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer),
                                   dw_shows.start_at)), 'YYYY-MM-DD')) <= (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW
                                   FROM coalesce(host_segments_gmv_start.end_date, GETDATE()))::integer),
                                   coalesce(host_segments_gmv_start.end_date, GETDATE()))), 'YYYY-MM-DD'))
WHERE origin_domain ='us' AND DATE(dw_shows.start_at) <= '2024-06-01'
          GROUP BY 1,2,3
union all
        SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
           coalesce(host_segments_gmv_start.host_segment_daily, 'Segment 1: No Sales') AS host_segment,
            'All'  AS Show_type,

           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id ELSE NULL END) AS Total_unique_show_Viewers,
           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN CONCAT(show_viewer_events.viewer_id ,show_viewer_events.show_id) ELSE NULL END) AS Total_show_Viewers,
           Count(distinct dw_shows.show_id) AS count_shows,
           Count(distinct dw_shows.creator_id) AS count_hosts,
           Total_show_Viewers/count_shows AS Avg_Viewers_per_show ,
           Total_show_Viewers/count_hosts AS Avg_Viewers_per_host
FROM analytics.dw_shows
          LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
           LEFT JOIN analytics_scratch.l365d_host_segment AS host_segments_gmv_start
                                   ON dw_shows.creator_id = host_segments_gmv_start.host_id AND
                                   (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)),'YYYY-MM-DD')) > (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM host_segments_gmv_start.start_date)::integer),
                                   host_segments_gmv_start.start_date)), 'YYYY-MM-DD')) and (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer),
                                   dw_shows.start_at)), 'YYYY-MM-DD')) <= (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW
                                   FROM coalesce(host_segments_gmv_start.end_date, GETDATE()))::integer),
                                   coalesce(host_segments_gmv_start.end_date, GETDATE()))), 'YYYY-MM-DD'))
WHERE origin_domain ='us' AND DATE(dw_shows.start_at) <= '2024-06-01'
          GROUP BY 1,2,3 order by 1 desc;




-------------------------------------------------------------------- Viewers by Host Segment and Show Type and Share show - weekly --------------------------------------------------------------------


SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
           coalesce(host_segments_gmv_start.host_segment_daily, 'Segment 1: No Sales') AS host_segment,
           CASE
               WHEN dw_shows.type = 'silent' then 'Silent Show'
                ELSE 'Live Show'
                    END AS Show_type,
          CASE WHEN curator_shows.show_id IS NOT NULL  THEN 'ST' ELSE 'Non ST' END AS Is_ST,

           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id ELSE NULL END) AS Total_unique_show_Viewers,
           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN CONCAT(show_viewer_events.viewer_id ,show_viewer_events.show_id) ELSE NULL END) AS Total_show_Viewers,
           Count(distinct dw_shows.show_id) AS count_shows,
           Count(distinct dw_shows.creator_id) AS count_hosts,
           Total_show_Viewers/count_shows AS Avg_Viewers_per_show ,
           Total_show_Viewers/count_hosts AS Avg_Viewers_per_host
FROM analytics.dw_shows
          LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
          LEFT JOIN looker_scratch.LR$H7IPD1717936706381_curator_shows AS curator_shows ON curator_shows.show_id = dw_shows.show_id
          LEFT JOIN analytics_scratch.l365d_host_segment AS host_segments_gmv_start
                                   ON dw_shows.creator_id = host_segments_gmv_start.host_id AND
                                   (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)),'YYYY-MM-DD')) > (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM host_segments_gmv_start.start_date)::integer),
                                   host_segments_gmv_start.start_date)), 'YYYY-MM-DD')) and (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer),
                                   dw_shows.start_at)), 'YYYY-MM-DD')) <= (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW
                                   FROM coalesce(host_segments_gmv_start.end_date, GETDATE()))::integer),
                                   coalesce(host_segments_gmv_start.end_date, GETDATE()))), 'YYYY-MM-DD'))
WHERE origin_domain ='us' AND DATE(dw_shows.start_at) <= '2024-06-01'
          GROUP BY 1,2,3,4
union all

SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
           'All' AS host_segment,
           CASE
               WHEN dw_shows.type = 'silent' then 'Silent Show'
                ELSE 'Live Show'
                    END AS Show_type,
           CASE WHEN curator_shows.show_id IS NOT NULL  THEN 'ST' ELSE 'Non ST' END AS Is_ST,

           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id ELSE NULL END) AS Total_unique_show_Viewers,
           Count(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN CONCAT(show_viewer_events.viewer_id ,show_viewer_events.show_id) ELSE NULL END) AS Total_show_Viewers,
           Count(distinct dw_shows.show_id) AS count_shows,
           Count(distinct dw_shows.creator_id) AS count_hosts,
           Total_show_Viewers/count_shows AS Avg_Viewers_per_show ,
           Total_show_Viewers/count_hosts AS Avg_Viewers_per_host
FROM analytics.dw_shows
          LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
          LEFT JOIN looker_scratch.LR$H7IPD1717936706381_curator_shows AS curator_shows ON curator_shows.show_id = dw_shows.show_id
          LEFT JOIN analytics_scratch.l365d_host_segment AS host_segments_gmv_start
                                   ON dw_shows.creator_id = host_segments_gmv_start.host_id AND
                                   (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)),'YYYY-MM-DD')) > (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM host_segments_gmv_start.start_date)::integer),
                                   host_segments_gmv_start.start_date)), 'YYYY-MM-DD')) and (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer),
                                   dw_shows.start_at)), 'YYYY-MM-DD')) <= (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW
                                   FROM coalesce(host_segments_gmv_start.end_date, GETDATE()))::integer),
                                   coalesce(host_segments_gmv_start.end_date, GETDATE()))), 'YYYY-MM-DD'))
WHERE origin_domain ='us' AND DATE(dw_shows.start_at) <= '2024-06-01'
          GROUP BY 1,2,3,4 order by 1 desc,2 ;


------------------------------ Unique Viewers by Viewers Segment (unique viewers who watched live , silent and both) --------------------------------------------------------------------

SELECT  base_table.show_start_week,
       count (DISTINCT CASE WHEN type_live is not null and type_silent is null THEN base_table.viewers_id ELSE NULL END  ) AS live_show_Unique_viewers,
       count (DISTINCT CASE WHEN type_live is  null and type_silent is not null THEN base_table.viewers_id ELSE NULL END  ) AS unique_silent_show_viewers,
       count (DISTINCT CASE WHEN type_live is not null and type_silent is not null THEN base_table.viewers_id ELSE NULL END  ) AS both_show_viewers

from (SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
    CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id END AS viewers_id
from analytics.dw_shows
LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
where origin_domain ='us' AND DATE(dw_shows.start_at) <= '2024-06-01' group by 1,2 order by 1 desc,2) As base_table
LEFT JOIN (SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
    CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id END AS viewers_id,
   type AS type_live
from analytics.dw_shows
LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
where origin_domain ='us' AND type = 'live' AND DATE(dw_shows.start_at) <= '2024-06-01' group by 1,2,3 order by 1 desc,2,3) As live_table

ON live_table.show_start_week = base_table.show_start_week
    AND live_table.viewers_id = base_table.viewers_id

LEFT JOIN (SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
    CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id END AS viewers_id,
   type AS type_silent
from analytics.dw_shows
LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
where origin_domain ='us' AND type = 'silent' AND DATE(dw_shows.start_at) <= '2024-06-01' group by 1,2,3 order by 1 desc,2,3 ) AS silent_table
ON silent_table.show_start_week = base_table.show_start_week
    AND silent_table.viewers_id = base_table.viewers_id
group by 1 order by 1 desc, 2 ;


-------------------------------------------------------------------- Unique Viewers by Viewers Segment across all the host segment --------------------------------------------------------------------


SELECT  base_table.show_start_week,
        host_segment,
       count (DISTINCT CASE WHEN type_live is not null and type_silent is null THEN base_table.viewers_id ELSE NULL END  ) AS live_show_Unique_viewers,
       count (DISTINCT CASE WHEN type_live is  null and type_silent is not null THEN base_table.viewers_id ELSE NULL END  ) AS unique_silent_show_viewers,
       count (DISTINCT CASE WHEN type_live is not null and type_silent is not null THEN base_table.viewers_id ELSE NULL END  ) AS both_show_viewers

from (SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
             coalesce(host_segments_gmv_start.host_segment_daily, 'Segment 1: No Sales') AS host_segment,
    CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id END AS viewers_id
from analytics.dw_shows
LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
LEFT JOIN  analytics_scratch.l365d_host_segment AS host_segments_gmv_start
                                   ON dw_shows.creator_id = host_segments_gmv_start.host_id AND
                                   (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)),'YYYY-MM-DD')) > (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM host_segments_gmv_start.start_date)::integer),
                                   host_segments_gmv_start.start_date)), 'YYYY-MM-DD')) and (TO_CHAR(
                                   DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer),
                                   dw_shows.start_at)), 'YYYY-MM-DD')) <= (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW
                                   FROM coalesce(host_segments_gmv_start.end_date, GETDATE()))::integer),
                                   coalesce(host_segments_gmv_start.end_date, GETDATE()))), 'YYYY-MM-DD'))
where dw_shows.origin_domain ='us' AND DATE(dw_shows.start_at) <= '2024-06-01' group by 1,2,3 order by 1 desc,2) As base_table
LEFT JOIN (SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
    CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id END AS viewers_id,
   type AS type_live
from analytics.dw_shows
LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
where origin_domain ='us' AND type = 'live' AND DATE(dw_shows.start_at) <= '2024-06-01' group by 1,2,3 order by 1 desc,2,3) As live_table

ON live_table.show_start_week = base_table.show_start_week
    AND live_table.viewers_id = base_table.viewers_id

LEFT JOIN (SELECT (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
    CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id END AS viewers_id,
   type AS type_silent
from analytics.dw_shows
LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
where origin_domain ='us' AND type = 'silent' AND DATE(dw_shows.start_at) <= '2024-06-01' group by 1,2,3 order by 1 desc,2,3 ) AS silent_table
ON silent_table.show_start_week = base_table.show_start_week
    AND silent_table.viewers_id = base_table.viewers_id
group by 1,2 order by 1 desc, 2 ;



-------------------------------------------------------------------- Active Users Vs Show Viewers --------------------------------------------------------------------


-- Define a CTE for calculating active users by week
WITH Active_Users_table AS (
    SELECT

        (TO_CHAR(DATE(DATEADD(day,(0 - EXTRACT(DOW FROM event_date )::integer), event_date)), 'YYYY-MM-DD')) AS event_date_week,
        -- Count distinct active and valid users
        COUNT(DISTINCT CASE WHEN is_active IS true AND is_valid_user IS true THEN user_id ELSE NULL END) AS Active_user
    FROM analytics.dw_user_events_daily
    WHERE (event_date <= '2024-06-01' AND event_date >= '2023-01-01') AND domain ='us'
    GROUP BY 1
),
-- Define a CTE for calculating total unique viewers by show week
Viewers_table AS (
    SELECT

        (TO_CHAR(DATE(DATEADD(day, (0 - EXTRACT(DOW FROM dw_shows.start_at)::integer), dw_shows.start_at)), 'YYYY-MM-DD')) AS show_start_week,
        -- Count distinct viewers excluding hosts
        COUNT(DISTINCT CASE WHEN show_viewer_events.viewer_id != show_viewer_events.host_id THEN show_viewer_events.viewer_id ELSE NULL END) AS Total_unique_Viewers
    FROM analytics.dw_shows
    LEFT JOIN analytics.dw_show_viewer_events_cs AS show_viewer_events ON show_viewer_events.show_id = dw_shows.show_id
    WHERE origin_domain ='us' AND (DATE(event_at) <= '2024-06-02' AND DATE(event_at) >= '2023-01-01')
    GROUP BY 1
)
-- Select weekly data, active users, total unique viewers, and calculate the ratio of viewers to active users
SELECT Active_Users_table.event_date_week,
       Active_Users_table.Active_user,
       Viewers_table.Total_unique_Viewers,
       -- Calculate the ratio of total unique viewers to active users
       (Total_unique_Viewers * 100.0 )/Active_user AS ratio
FROM Active_Users_table
LEFT JOIN Viewers_table ON Viewers_table.show_start_week = Active_Users_table.event_date_week
ORDER BY 1 DESC;
