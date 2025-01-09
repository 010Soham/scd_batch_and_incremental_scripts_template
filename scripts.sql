
CREATE TYPE fiscal_metrics AS (
    fiscal_year       INTEGER,   
    total_count       INTEGER,   
    measure_1         NUMERIC,   
    measure_2         NUMERIC,   
    measure_3         NUMERIC    
);

CREATE TYPE performance_band AS ENUM ('star', 'good', 'average', 'bad');


CREATE TABLE customers (
    customer_id              TEXT,            
    dimension_1              TEXT,            
    source_system            TEXT,            
    country_of_origin        TEXT,            
    registration_year        TEXT,            
    registration_round       TEXT,            
    registration_number      TEXT,            
    fiscal_data              fiscal_metrics[],
    performance_category     performance_band,
    years_since_last_activity INTEGER,        
    current_fiscal_year      INTEGER,         
    is_currently_active      BOOLEAN,         
    PRIMARY KEY (customer_id, current_fiscal_year)
);



SELECT *
FROM customer_fiscal_periods
ORDER BY customer_id, fiscal_period;







INSERT INTO customers
WITH fiscal_years AS (
    SELECT *
    FROM GENERATE_SERIES(1996, 2022) AS fiscal_period
), 
c AS (
    SELECT
        customer_id,
        MIN(fiscal_period) AS first_fiscal_period
    FROM customer_fiscal_periods
    GROUP BY customer_id
), customers_and_periods AS (
    
    SELECT *
    FROM c
    JOIN fiscal_years fy
        ON c.first_fiscal_period <= fy.fiscal_period
), windowed AS (
    SELECT
        cap.customer_id,
        cap.fiscal_period,
        -- possibilty of null for customer data in customer_fiscal_periods table
        ARRAY_REMOVE(
            ARRAY_AGG(
                CASE
                    WHEN cfp.fiscal_period IS NOT NULL THEN
                        ROW(
                            cfp.fiscal_period,  
                            cfp.total_count,    
                            cfp.measure_1,      
                            cfp.measure_2,      
                            cfp.measure_3       
                        )::fiscal_metrics     
                END
            ) OVER (
                PARTITION BY cap.customer_id
                ORDER BY COALESCE(cap.fiscal_period, cfp.fiscal_period)
            ),
            NULL
        ) AS fiscal_data  
    FROM customers_and_periods cap
    LEFT JOIN customer_fiscal_periods cfp
        ON cap.customer_id  = cfp.customer_id
       AND cap.fiscal_period = cfp.fiscal_period
    ORDER BY cap.customer_id, cap.fiscal_period
), static AS (
    
    SELECT
        customer_id,
        MAX(dimension_1) AS dimension_1,         
        MAX(source_system) AS source_system,       
        MAX(country_of_origin) AS country_of_origin,    
        MAX(registration_year) AS registration_year,    
        MAX(registration_round) AS registration_round,   
        MAX(registration_number) AS registration_number   
    FROM customer_fiscal_periods
    GROUP BY customer_id
)
SELECT
    w.customer_id,
    s.dimension_1,
    s.source_system,
    s.country_of_origin,
    s.registration_year,
    s.registration_round,
    s.registration_number,
    fiscal_data,  
    CASE
        
        WHEN (fiscal_data[CARDINALITY(fiscal_data)]::fiscal_metrics).measure_1 > 20 THEN 'star'
        WHEN (fiscal_data[CARDINALITY(fiscal_data)]::fiscal_metrics).measure_1 > 15 THEN 'good'
        WHEN (fiscal_data[CARDINALITY(fiscal_data)]::fiscal_metrics).measure_1 > 10 THEN 'average'
        ELSE 'bad'
    END::performance_band AS performance_category,  -- was scoring_class
    w.fiscal_period - (fiscal_data[CARDINALITY(fiscal_data)]::fiscal_metrics).fiscal_year
         AS years_since_last_activity,              -- was years_since_last_active
    w.fiscal_period,
    (fiscal_data[CARDINALITY(fiscal_data)]::fiscal_metrics).fiscal_year = w.fiscal_period
         AS is_currently_active                     -- was is_active
FROM windowed w
JOIN static s
    ON w.customer_id = s.customer_id;



SELECT 
    customer_id          
  , performance_category 
  , is_currently_active  
FROM customers           
WHERE current_fiscal_year = 2022; 






CREATE TABLE customers_scd (
    customer_id            TEXT,               
    performance_category   performance_band,   
    is_currently_active    BOOLEAN,            
    start_fiscal_year      INTEGER,            
    end_fiscal_year        INTEGER,            
    current_fiscal_year    INTEGER,            
    PRIMARY KEY (customer_id, current_fiscal_year)
);



SELECT 
    customer_id AS customer_id,                    
    current_fiscal_year AS current_fiscal_year,    
    performance_category AS performance_category,   
    LAG(performance_category, 1) 
        OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
        AS previous_performance_category,           
    LAG(is_currently_active, 1) 
        OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
        AS previous_is_currently_active,            
    is_currently_active                             
FROM customers;                                     



WITH with_previous AS (
    SELECT
        customer_id AS customer_id,                              
        current_fiscal_year AS current_fiscal_year,              
        performance_category AS performance_category,            
        LAG(performance_category, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
            AS previous_performance_category,                    
        LAG(is_currently_active, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
            AS previous_is_currently_active,                     
        is_currently_active AS is_currently_active               
    FROM customers                                               
)
SELECT 
    *,
    CASE 
        WHEN performance_category <> previous_performance_category THEN 1
        ELSE 0
    END AS performance_category_change_indicator,                
    CASE 
        WHEN is_currently_active <> previous_is_currently_active THEN 1
        ELSE 0
    END AS is_currently_active_change_indicator                  
FROM with_previous;





WITH with_previous AS (
    SELECT 
        customer_id AS customer_id,                              
        current_fiscal_year AS current_fiscal_year,              
        performance_category AS performance_category,            
        LAG(performance_category, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
            AS previous_performance_category,                    
        LAG(is_currently_active, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
            AS previous_is_currently_active,                     
        is_currently_active AS is_currently_active               
    FROM customers                                               
),
with_indicators AS (
    SELECT
        *,
        CASE
            WHEN performance_category <> previous_performance_category THEN 1
            WHEN is_currently_active <> previous_is_currently_active THEN 1
            ELSE 0
        END AS change_indicator
    FROM with_previous
);




WITH with_previous AS (
    SELECT
        customer_id AS customer_id,                              
        current_fiscal_year AS current_fiscal_year,              
        performance_category AS performance_category,            
        LAG(performance_category, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
            AS previous_performance_category,                    
        LAG(is_currently_active, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
            AS previous_is_currently_active,                     
        is_currently_active AS is_currently_active               
    FROM customers                                               
),
with_indicators AS (
    SELECT
        *,
        CASE 
            WHEN performance_category <> previous_performance_category THEN 1
            WHEN is_currently_active <> previous_is_currently_active THEN 1
            ELSE 0
        END AS change_indicator
    FROM with_previous
),
with_streaks AS (
    SELECT
        *,
        SUM(change_indicator)
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
            AS streak_identifier
    FROM with_indicators
);




WITH with_previous AS (
    SELECT
        customer_id AS customer_id,                               
        current_fiscal_year AS current_fiscal_year,               
        performance_category AS performance_category,             
        LAG(performance_category, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
            AS previous_performance_category,                     
        LAG(is_currently_active, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) 
            AS previous_is_currently_active,                      
        is_currently_active AS is_currently_active                
    FROM customers                                                
    WHERE current_fiscal_year <= 2021
),
with_indicators AS (
    SELECT
        *,
        CASE 
            WHEN performance_category <> previous_performance_category THEN 1
            WHEN is_currently_active <> previous_is_currently_active THEN 1
            ELSE 0
        END AS change_indicator
    FROM with_previous
),
with_streaks AS (
    SELECT
        *,
        SUM(change_indicator)
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) AS streak_identifier
    FROM with_indicators
)
SELECT
    customer_id AS customer_id,                                   
    streak_identifier,
    is_currently_active AS is_currently_active,                   
    performance_category AS performance_category,                 
    MIN(current_fiscal_year) AS start_fiscal_year,                
    MAX(current_fiscal_year) AS end_fiscal_year                   
FROM with_streaks
GROUP BY 
    customer_id,
    streak_identifier,
    is_currently_active,
    performance_category;



CREATE TABLE customers_scd (
    customer_id           TEXT,                -- was player_name
    performance_category  performance_band,    -- was scoring_class
    is_currently_active   BOOLEAN,             -- was is_active
    start_fiscal_year     INTEGER,             -- was start_season
    end_fiscal_year       INTEGER,             -- was end_season
    current_fiscal_year   INTEGER,             -- was current_season
    PRIMARY KEY (customer_id, start_fiscal_year)
);




INSERT INTO customers_scd  
WITH with_previous AS (
    SELECT
        customer_id AS customer_id,                           
        current_fiscal_year AS current_fiscal_year,            
        performance_category AS performance_category,          
        LAG(performance_category, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year)
            AS previous_performance_category,                  
        LAG(is_currently_active, 1) 
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year)
            AS previous_is_currently_active,                   
        is_currently_active AS is_currently_active             
    FROM customers                                             
    WHERE current_fiscal_year <= 2021
),
with_indicators AS (
    SELECT
        *,
        CASE 
            WHEN performance_category <> previous_performance_category THEN 1
            WHEN is_currently_active <> previous_is_currently_active THEN 1
            ELSE 0
        END AS change_indicator
    FROM with_previous
),
with_streaks AS (
    SELECT
        *,
        SUM(change_indicator)
            OVER (PARTITION BY customer_id ORDER BY current_fiscal_year) AS streak_identifier
    FROM with_indicators
)
SELECT
    customer_id,                                              
    performance_category,                                     
    is_currently_active,                                      
    MIN(current_fiscal_year) AS start_fiscal_year,            
    MAX(current_fiscal_year) AS end_fiscal_year,              
    2021 AS current_fiscal_year                               
FROM with_streaks
GROUP BY 
    customer_id,
    streak_identifier,
    is_currently_active,
    performance_category
ORDER BY 
    customer_id,
    streak_identifier;



-- incremental loading



WITH last_season_scd AS (
    SELECT * 
    FROM customers_scd                               
    WHERE current_fiscal_year = 2021                 
      AND end_fiscal_year = 2021                     
),
historical_scd AS (
    SELECT *
    FROM customers_scd                               
    WHERE current_fiscal_year = 2021                 
      AND end_fiscal_year < 2021                     
),
this_season_data AS (
    SELECT *
    FROM customers                                   
    WHERE current_fiscal_year = 2022                 
)
SELECT 
    ts.customer_id,                                  
    ts.performance_category,                         
    ts.is_currently_active,                          
    ls.performance_category,                         
    ls.is_currently_active                           
FROM this_season_data ts
LEFT JOIN last_season_scd ls
    ON ls.customer_id = ts.customer_id;              



WITH last_season_scd AS (
    SELECT * 
    FROM customers_scd                              
    WHERE current_fiscal_year = 2021                
      AND end_fiscal_year = 2021                    
),
historical_scd AS (
    SELECT * 
    FROM customers_scd                              
    WHERE current_fiscal_year = 2021                
      AND end_fiscal_year < 2021                    
),
this_season_data AS (
    SELECT *
    FROM customers                                  
    WHERE current_fiscal_year = 2022                
),
unchanged_records AS (
    SELECT
        ts.customer_id,                             
        ts.performance_category,                    
        ts.is_currently_active,                     
        ls.performance_category,                    
        ls.is_currently_active                      
    FROM this_season_data ts
    JOIN last_season_scd ls
        ON ls.customer_id = ts.customer_id          
    WHERE 
        ts.performance_category = ls.performance_category
        AND ts.is_currently_active = ls.is_currently_active
);



WITH last_season_scd AS (
    SELECT * 
    FROM customers_scd                              
    WHERE current_fiscal_year = 2021                
      AND end_fiscal_year = 2021                    
),
historical_scd AS (
    SELECT * 
    FROM customers_scd                              
    WHERE current_fiscal_year = 2021                
      AND end_fiscal_year < 2021                    
),
this_season_data AS (
    SELECT *
    FROM customers                                  
    WHERE current_fiscal_year = 2022                
),
unchanged_records AS (
    SELECT 
        ts.customer_id,                             
        ts.performance_category,                    
        ts.is_currently_active,                     
        ls.performance_category,                    
        ls.is_currently_active                      
    FROM this_season_data ts
    JOIN last_season_scd ls
        ON ls.customer_id = ts.customer_id          
    WHERE 
        ts.performance_category = ls.performance_category
        AND ts.is_currently_active = ls.is_currently_active
),
new_and_changed_records AS (
    SELECT 
        ts.customer_id,                             
        ts.performance_category,                    
        ts.is_currently_active,                     
        ls.start_fiscal_year,                       
        ts.current_fiscal_year AS end_fiscal_year   
    FROM this_season_data ts
    LEFT JOIN last_season_scd ls
        ON ls.customer_id = ts.customer_id          
    WHERE 
        (ts.performance_category <> ls.performance_category
         OR ts.is_currently_active <> ls.is_currently_active
         OR ls.customer_id IS NULL)                 
)
SELECT *
FROM new_and_changed_records;





CREATE TYPE scd_snapshot AS (
    performance_category performance_band,   
    is_currently_active  BOOLEAN,            
    start_fiscal_year    INTEGER,            
    end_fiscal_year      INTEGER             
);

WITH last_season_scd AS (
    SELECT * 
    FROM customers_scd                                 
    WHERE current_fiscal_year = 2021                   
      AND end_fiscal_year = 2021                       
),
historical_scd AS (
    SELECT * 
    FROM customers_scd                                 
    WHERE current_fiscal_year = 2021                   
      AND end_fiscal_year < 2021                       
),
this_season_data AS (
    SELECT *
    FROM customers                                     
    WHERE current_fiscal_year = 2022                   
),
unchanged_records AS (
    SELECT 
        ts.customer_id,                                
        ts.performance_category,                       
        ts.is_currently_active,                        
        ls.performance_category,                       
        ls.is_currently_active                         
    FROM this_season_data ts
    JOIN last_season_scd ls
        ON ls.customer_id = ts.customer_id            
    WHERE 
        ts.performance_category = ls.performance_category
        AND ts.is_currently_active = ls.is_currently_active
),
new_and_changed_records AS (
    SELECT
        ts.customer_id,                                
        UNNEST(
            ARRAY[
                ROW(
                    ls.performance_category,          
                    ls.is_currently_active,           
                    ls.start_fiscal_year,             
                    ls.end_fiscal_year                
                )::scd_snapshot,                      
                ROW(
                    ts.performance_category,          
                    ts.is_currently_active,           
                    ts.current_fiscal_year,           
                    ts.current_fiscal_year            
                )::scd_snapshot
            ]
        )
    FROM this_season_data ts
    LEFT JOIN last_season_scd ls
        ON ls.customer_id = ts.customer_id             
    WHERE 
        ts.performance_category <> ls.performance_category
        OR ts.is_currently_active <> ls.is_currently_active
)
SELECT *
FROM new_and_changed_records;





CREATE TYPE scd_snapshot AS (
    performance_category performance_band, 
    is_currently_active  BOOLEAN,          
    start_fiscal_year    INTEGER,          
    end_fiscal_year      INTEGER           
);

WITH last_season_scd AS (
    SELECT * 
    FROM customers_scd                             
    WHERE current_fiscal_year = 2021                
      AND end_fiscal_year = 2021                    
),
historical_scd AS (
    SELECT *
    FROM customers_scd                             
    WHERE current_fiscal_year = 2021               
      AND end_fiscal_year < 2021                   
),
this_season_data AS (
    SELECT *
    FROM customers                                 
    WHERE current_fiscal_year = 2022               
),
unchanged_records AS (
    SELECT 
        ts.customer_id,                            
        ts.performance_category,                   
        ts.is_currently_active,                    
        ls.performance_category,                   
        ls.is_currently_active                     
    FROM this_season_data ts
    JOIN last_season_scd ls
        ON ls.customer_id = ts.customer_id         
    WHERE 
        ts.performance_category = ls.performance_category
        AND ts.is_currently_active = ls.is_currently_active
),
changed_records AS (
    SELECT 
        ts.customer_id,                             
        UNNEST(
            ARRAY[
                ROW(
                    ls.performance_category,        
                    ls.is_currently_active,         
                    ls.start_fiscal_year,           
                    ls.end_fiscal_year             
                )::scd_snapshot,                   
                ROW(
                    ts.performance_category,        
                    ts.is_currently_active,         
                    ts.current_fiscal_year,         
                    ts.current_fiscal_year          
                )::scd_snapshot
            ]
        ) AS records
    FROM this_season_data ts
    LEFT JOIN last_season_scd ls
        ON ls.customer_id = ts.customer_id          
    WHERE 
        ts.performance_category <> ls.performance_category
        OR ts.is_currently_active <> ls.is_currently_active
),
unnested_changed_records AS (
    SELECT 
        customer_id,                                
        (records::scd_snapshot).performance_category,
        (records::scd_snapshot).is_currently_active,
        (records::scd_snapshot).start_fiscal_year,
        (records::scd_snapshot).end_fiscal_year
    FROM changed_records
)
SELECT *
FROM unnested_changed_records;





WITH last_season_scd AS (
    SELECT * 
    FROM customers_scd                              
    WHERE current_fiscal_year = 2021                
      AND end_fiscal_year = 2021                    
),
historical_scd AS (
    SELECT
        customer_id        AS customer_id,          
        performance_category AS performance_category, 
        is_currently_active  AS is_currently_active,
        start_fiscal_year    AS start_fiscal_year,  
        end_fiscal_year      AS end_fiscal_year     
    FROM customers_scd                              
    WHERE current_fiscal_year = 2021                
      AND end_fiscal_year < 2021                    
),
this_season_data AS (
    SELECT *
    FROM customers                                   
    WHERE current_fiscal_year = 2022                
),
unchanged_records AS (
    SELECT 
        ts.customer_id         AS customer_id,      
        ts.performance_category AS performance_category,   
        ts.is_currently_active  AS is_currently_active,    
        ls.performance_category AS previous_performance_category, 
        ls.is_currently_active  AS previous_is_currently_active   
    FROM this_season_data ts
    JOIN last_season_scd ls
        ON ls.customer_id = ts.customer_id          
    WHERE 
        ts.performance_category   = ls.performance_category
        AND ts.is_currently_active = ls.is_currently_active
),
changed_records AS (
    SELECT 
        ts.customer_id AS customer_id,             
        UNNEST(
            ARRAY[
                ROW(
                    ls.performance_category,       
                    ls.is_currently_active,        
                    ls.start_fiscal_year,          
                    ls.end_fiscal_year             
                )::scd_snapshot,                   
                ROW(
                    ts.performance_category,       
                    ts.is_currently_active,        
                    ts.current_fiscal_year,        
                    ts.current_fiscal_year         
                )::scd_snapshot
            ]
        ) AS records
    FROM this_season_data ts
    LEFT JOIN last_season_scd ls
        ON ls.customer_id = ts.customer_id          
    WHERE 
        (ts.performance_category  <> ls.performance_category
         OR ts.is_currently_active <> ls.is_currently_active)
),
unnested_changed_records AS (
    SELECT 
        customer_id,                                
        (records::scd_snapshot).performance_category  AS performance_category, 
        (records::scd_snapshot).is_currently_active   AS is_currently_active,  
        (records::scd_snapshot).start_fiscal_year     AS start_fiscal_year,    
        (records::scd_snapshot).end_fiscal_year       AS end_fiscal_year       
    FROM changed_records
),
new_records AS (
    SELECT
        ts.customer_id          AS customer_id,     
        ts.performance_category AS performance_category,  
        ts.is_currently_active  AS is_currently_active,   
        ts.current_fiscal_year  AS start_fiscal_year,     
        ts.current_fiscal_year  AS end_fiscal_year        
    FROM this_season_data ts
    LEFT JOIN last_season_scd ls
        ON ts.customer_id = ls.customer_id         
    WHERE ls.customer_id IS NULL
)
SELECT * FROM historical_scd
UNION ALL
SELECT * FROM unchanged_records
UNION ALL
SELECT * FROM unnested_changed_records
UNION ALL
SELECT * FROM new_records;
