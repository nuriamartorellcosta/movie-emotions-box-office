-- Final database creation and analysis script
CREATE TABLE public.movie (
    movie_id INTEGER PRIMARY KEY,
    metacritic_url TEXT UNIQUE,
    title TEXT NOT NULL,
    studio TEXT,
    rating VARCHAR(50),
    summary TEXT,
    runtime INTEGER,
    director TEXT,
    metascore INTEGER,
    release_date DATE,
    keywords TEXT,
    creative_type TEXT
);

-- GENRE table - stores each genre once
CREATE TABLE public.genre (
    genre_id INTEGER PRIMARY KEY,
    genre_name TEXT UNIQUE NOT NULL
);

-- ACTOR table - stores each actor once
CREATE TABLE public.actor (
    actor_id INTEGER PRIMARY KEY,
    actor_name TEXT UNIQUE NOT NULL
);

-- AWARD table - stores each award once
CREATE TABLE public.award (
    award_id INTEGER PRIMARY KEY,
    award_name TEXT UNIQUE NOT NULL
);

-- SALES table - stores one financial record per movie
CREATE TABLE public.sales (
    movie_id INTEGER PRIMARY KEY,
    year INTEGER,
    production_budget NUMERIC(20,2),
    domestic_box_office NUMERIC(20,2),
    international_box_office NUMERIC(20,2),
    worldwide_box_office NUMERIC(20,2),
    opening_weekend NUMERIC(20,2),
    theatre_count INTEGER,

    FOREIGN KEY (movie_id)
        REFERENCES public.movie(movie_id) -- this prevents sales records from using a movie_id that does not exist
);

-- EXPERT_REVIEW table - stores individual critic reviews
CREATE TABLE public.expert_review (
    review_id INTEGER PRIMARY KEY,
    movie_id INTEGER NOT NULL,
    reviewer TEXT,
    date_posted DATE,
    review_text TEXT NOT NULL,
    review_score NUMERIC(6,2),
    word_count INTEGER,
    tone DOUBLE PRECISION,
    posemo DOUBLE PRECISION,
    negemo DOUBLE PRECISION,
    anx DOUBLE PRECISION,
    anger DOUBLE PRECISION,
    sad DOUBLE PRECISION,

    FOREIGN KEY (movie_id)
        REFERENCES public.movie(movie_id) -- this connects each expert review to an existing movie
);

-- CONSUMER_REVIEW table - stores individual audience reviews
CREATE TABLE public.consumer_review (
    review_id INTEGER PRIMARY KEY,
    movie_id INTEGER NOT NULL,
    reviewer TEXT,
    date_posted DATE,
    review_text TEXT NOT NULL,
    review_score NUMERIC(6,2),
    thumbs_up INTEGER,
    thumbs_total INTEGER,
    word_count INTEGER,
    tone DOUBLE PRECISION,
    posemo DOUBLE PRECISION,
    negemo DOUBLE PRECISION,
    anx DOUBLE PRECISION,
    anger DOUBLE PRECISION,
    sad DOUBLE PRECISION,

    FOREIGN KEY (movie_id)
        REFERENCES public.movie(movie_id) -- this connects each consumer review to an existing movie
);

-- MOVIE_GENRE junction table - connects movies and genres
CREATE TABLE public.movie_genre (
    movie_id INTEGER NOT NULL,
    genre_id INTEGER NOT NULL,

    PRIMARY KEY (movie_id, genre_id), -- this prevents duplicate movie-genre relationships

    FOREIGN KEY (movie_id)
        REFERENCES public.movie(movie_id), -- this requires a valid movie

    FOREIGN KEY (genre_id)
        REFERENCES public.genre(genre_id) -- this requires a valid genre
);

-- MOVIE_CAST junction table - connects movies and actors
CREATE TABLE public.movie_cast (
    movie_id INTEGER NOT NULL,
    actor_id INTEGER NOT NULL,

    PRIMARY KEY (movie_id, actor_id), -- this prevents duplicate movie-actor relationships

    FOREIGN KEY (movie_id)
        REFERENCES public.movie(movie_id), -- this requires a valid movie

    FOREIGN KEY (actor_id)
        REFERENCES public.actor(actor_id) -- this requires a valid actor
);

-- MOVIE_AWARD junction table - connects movies and awards
CREATE TABLE public.movie_award (
    movie_id INTEGER NOT NULL,
    award_id INTEGER NOT NULL,

    PRIMARY KEY (movie_id, award_id), -- this prevents duplicate movie-award relationships

    FOREIGN KEY (movie_id)
        REFERENCES public.movie(movie_id), -- this requires a valid movie

    FOREIGN KEY (award_id)
        REFERENCES public.award(award_id) -- this requires a valid award
);


-- Analysis view - Alexandra, Zein, Nuria
-- Consumer and expert review data converted from review level to movie level

CREATE OR REPLACE VIEW public.movie_emotion_analysis AS

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS consumer_posemo, -- this averages consumer positive emotion per movie
        AVG(negemo) AS consumer_negemo, -- this averages consumer negative emotion per movie
        AVG(tone) AS consumer_tone, -- this averages consumer tone per movie
        AVG(anx) AS consumer_anx, -- this averages consumer anxiety per movie
        AVG(anger) AS consumer_anger, -- this averages consumer anger per movie
        AVG(sad) AS consumer_sad -- this averages consumer sadness per movie
    FROM public.consumer_review
    GROUP BY movie_id -- this changes many reviews into one row per movie
),

expert_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS expert_posemo, -- this averages expert positive emotion per movie
        AVG(negemo) AS expert_negemo, -- this averages expert negative emotion per movie
        AVG(tone) AS expert_tone, -- this averages expert tone per movie
        AVG(anx) AS expert_anx, -- this averages expert anxiety per movie
        AVG(anger) AS expert_anger, -- this averages expert anger per movie
        AVG(sad) AS expert_sad -- this averages expert sadness per movie
    FROM public.expert_review
    GROUP BY movie_id -- this changes many reviews into one row per movie
)

SELECT
    s.movie_id,
    s.year,
    s.production_budget,
    s.domestic_box_office,
    s.international_box_office,
    s.worldwide_box_office,
    s.opening_weekend,
    s.theatre_count,

    c.consumer_posemo,
    c.consumer_negemo,
    c.consumer_tone,
    c.consumer_anx,
    c.consumer_anger,
    c.consumer_sad,

    e.expert_posemo,
    e.expert_negemo,
    e.expert_tone,
    e.expert_anx,
    e.expert_anger,
    e.expert_sad

FROM public.sales s

LEFT JOIN consumer_avg c
    ON s.movie_id = c.movie_id -- this connects consumer emotions to sales

LEFT JOIN expert_avg e
    ON s.movie_id = e.movie_id; -- this connects expert emotions to sales



-- SQ1 Q1: Positive consumer emotion vs worldwide box office - Pearson - Alexandra

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS avg_consumer_posemo -- this averages positive consumer emotion per movie
    FROM public.consumer_review
    GROUP BY movie_id -- this changes review-level data into one row per movie
),

data AS (
    SELECT
        s.movie_id,
        c.avg_consumer_posemo AS emotion,
        LN(s.worldwide_box_office) AS box_office -- this log-transforms worldwide revenue
    FROM public.sales s

    JOIN consumer_avg c
        ON s.movie_id = c.movie_id -- this connects consumer emotions to the matching sales record

    WHERE s.worldwide_box_office > 0 -- this removes zero or negative revenue before LN()
    AND c.avg_consumer_posemo IS NOT NULL -- this removes missing emotion values
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1, -- this calculates the lower emotion quartile
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3, -- this calculates the upper emotion quartile
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1, -- this calculates the lower box-office quartile
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3 -- this calculates the upper box-office quartile
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)
        -- this removes emotion outliers using the 1.5 x IQR rule

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this removes box-office outliers using the 1.5 x IQR rule
)

SELECT
    CORR(emotion, box_office) AS pearson_r, -- this calculates the Pearson correlation
    (SELECT COUNT(*) FROM data) AS movies_before, -- this counts movies before outlier removal
    COUNT(*) AS movies_used, -- this counts movies after outlier removal
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed -- this counts removed observations
FROM filtered;



-- SQ1 Q1: Positive consumer emotion vs worldwide box office - Spearman - Alexandra

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS avg_consumer_posemo -- this averages positive consumer emotion per movie
    FROM public.consumer_review
    GROUP BY movie_id -- this changes review-level data into one row per movie
),

data AS (
    SELECT
        s.movie_id,
        c.avg_consumer_posemo AS emotion,
        LN(s.worldwide_box_office) AS box_office -- this log-transforms worldwide revenue
    FROM public.sales s

    JOIN consumer_avg c
        ON s.movie_id = c.movie_id -- this connects consumer emotions to the matching sales record

    WHERE s.worldwide_box_office > 0 -- this removes zero or negative revenue before LN()
    AND c.avg_consumer_posemo IS NOT NULL -- this removes missing emotion values
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)
        -- this removes emotion outliers using the 1.5 x IQR rule

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this removes box-office outliers using the 1.5 x IQR rule
),

ranked AS (
    SELECT
        movie_id,

        RANK() OVER (ORDER BY emotion)
        + (COUNT(*) OVER (PARTITION BY emotion) - 1) / 2.0
        AS emotion_rank, -- this converts emotion values into average ranks

        RANK() OVER (ORDER BY box_office)
        + (COUNT(*) OVER (PARTITION BY box_office) - 1) / 2.0
        AS box_office_rank -- this converts box-office values into average ranks

    FROM filtered
)

SELECT
    CORR(emotion_rank, box_office_rank) AS spearman_rho, -- this calculates the Spearman correlation
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM ranked;



-- SQ1 Q2: Positive consumer emotion vs domestic box office - Pearson - Alexandra

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS avg_consumer_posemo -- this averages positive consumer emotion per movie
    FROM public.consumer_review
    GROUP BY movie_id
),

data AS (
    SELECT
        s.movie_id,
        c.avg_consumer_posemo AS emotion,
        LN(s.domestic_box_office) AS box_office -- this log-transforms domestic revenue
    FROM public.sales s

    JOIN consumer_avg c
        ON s.movie_id = c.movie_id -- this connects consumer emotions to sales

    WHERE s.domestic_box_office > 0 -- this removes zero or negative revenue before LN()
    AND c.avg_consumer_posemo IS NOT NULL -- this removes missing emotion values
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)
        -- this removes emotion outliers using the 1.5 x IQR rule

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this removes box-office outliers using the 1.5 x IQR rule
)

SELECT
    CORR(emotion, box_office) AS pearson_r, -- this calculates the Pearson correlation
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM filtered;



-- SQ1 Q2: Positive consumer emotion vs domestic box office - Spearman - Alexandra

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS avg_consumer_posemo
    FROM public.consumer_review
    GROUP BY movie_id
),

data AS (
    SELECT
        s.movie_id,
        c.avg_consumer_posemo AS emotion,
        LN(s.domestic_box_office) AS box_office -- this log-transforms domestic revenue
    FROM public.sales s

    JOIN consumer_avg c
        ON s.movie_id = c.movie_id -- this connects consumer emotions to sales

    WHERE s.domestic_box_office > 0
    AND c.avg_consumer_posemo IS NOT NULL
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)
        -- this removes emotion outliers using the 1.5 x IQR rule

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this removes box-office outliers using the 1.5 x IQR rule
),

ranked AS (
    SELECT
        movie_id,

        RANK() OVER (ORDER BY emotion)
        + (COUNT(*) OVER (PARTITION BY emotion) - 1) / 2.0
        AS emotion_rank, -- this converts emotion values into ranks

        RANK() OVER (ORDER BY box_office)
        + (COUNT(*) OVER (PARTITION BY box_office) - 1) / 2.0
        AS box_office_rank -- this converts box-office values into ranks

    FROM filtered
)

SELECT
    CORR(emotion_rank, box_office_rank) AS spearman_rho, -- this calculates Spearman
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM ranked;



-- SQ1 Q3: Positive consumer emotion vs opening weekend box office - Pearson - Alexandra

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS avg_consumer_posemo
    FROM public.consumer_review
    GROUP BY movie_id
),

data AS (
    SELECT
        s.movie_id,
        c.avg_consumer_posemo AS emotion,
        LN(s.opening_weekend) AS box_office -- this log-transforms opening-weekend revenue
    FROM public.sales s

    JOIN consumer_avg c
        ON s.movie_id = c.movie_id -- this connects consumer emotions to sales

    WHERE s.opening_weekend > 0 -- this removes zero or negative values before LN()
    AND c.avg_consumer_posemo IS NOT NULL
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)
        -- this removes emotion outliers using the 1.5 x IQR rule

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this removes box-office outliers using the 1.5 x IQR rule
)

SELECT
    CORR(emotion, box_office) AS pearson_r, -- this calculates Pearson
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM filtered;



-- SQ1 Q3: Positive consumer emotion vs opening weekend box office - Spearman - Alexandra

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS avg_consumer_posemo
    FROM public.consumer_review
    GROUP BY movie_id
),

data AS (
    SELECT
        s.movie_id,
        c.avg_consumer_posemo AS emotion,
        LN(s.opening_weekend) AS box_office -- this log-transforms opening-weekend revenue
    FROM public.sales s

    JOIN consumer_avg c
        ON s.movie_id = c.movie_id

    WHERE s.opening_weekend > 0
    AND c.avg_consumer_posemo IS NOT NULL
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
),

ranked AS (
    SELECT
        movie_id,

        RANK() OVER (ORDER BY emotion)
        + (COUNT(*) OVER (PARTITION BY emotion) - 1) / 2.0
        AS emotion_rank, -- this converts emotion values into ranks

        RANK() OVER (ORDER BY box_office)
        + (COUNT(*) OVER (PARTITION BY box_office) - 1) / 2.0
        AS box_office_rank -- this converts box-office values into ranks

    FROM filtered
)

SELECT
    CORR(emotion_rank, box_office_rank) AS spearman_rho, -- this calculates Spearman
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM ranked;



-- SQ2 Q1: Negative consumer emotion vs worldwide box office - Zein
-- SQ2 Q2: Negative consumer emotion vs domestic box office - Zein
-- SQ2 Q3: Negative consumer emotion vs opening weekend box office - Zein
-- Additional: Consumer anxiety, anger and sadness vs worldwide box office - Zein

WITH base AS (
    SELECT
        m.consumer_negemo,
        m.worldwide_box_office,
        m.domestic_box_office,
        m.opening_weekend,
        c.anx,
        c.anger,
        c.sad

    FROM public.movie_emotion_analysis m

    JOIN (
        SELECT
            movie_id,
            AVG(anx) AS anx, -- this averages consumer anxiety per movie
            AVG(anger) AS anger, -- this averages consumer anger per movie
            AVG(sad) AS sad -- this averages consumer sadness per movie
        FROM public.consumer_review
        GROUP BY movie_id -- this changes review-level values into movie-level values
    ) c
        ON m.movie_id = c.movie_id -- this connects specific negative emotions to the analysis data

    WHERE m.worldwide_box_office > 0
      AND m.domestic_box_office > 0
      AND m.opening_weekend > 0 -- this keeps valid positive revenue values

      AND m.consumer_negemo IS NOT NULL
      AND c.anx IS NOT NULL
      AND c.anger IS NOT NULL
      AND c.sad IS NOT NULL -- this removes incomplete emotion observations
),

long AS (
    SELECT
        '1 negemo_worldwide' AS test,
        consumer_negemo AS x,
        worldwide_box_office AS y
    FROM base -- this tests negative consumer emotion against worldwide box office

    UNION ALL

    SELECT
        '2 negemo_domestic',
        consumer_negemo,
        domestic_box_office
    FROM base -- this tests negative consumer emotion against domestic box office

    UNION ALL

    SELECT
        '3 negemo_opening',
        consumer_negemo,
        opening_weekend
    FROM base -- this tests negative consumer emotion against opening weekend

    UNION ALL

    SELECT
        '4a anx_worldwide',
        anx,
        worldwide_box_office
    FROM base -- this tests consumer anxiety against worldwide box office

    UNION ALL

    SELECT
        '4b anger_worldwide',
        anger,
        worldwide_box_office
    FROM base -- this tests consumer anger against worldwide box office

    UNION ALL

    SELECT
        '4c sad_worldwide',
        sad,
        worldwide_box_office
    FROM base -- this tests consumer sadness against worldwide box office
),

ranked AS (
    SELECT
        test,
        x,
        y,

        RANK() OVER (PARTITION BY test ORDER BY x)
        + (COUNT(*) OVER (PARTITION BY test, x) - 1) / 2.0
        AS rank_x, -- this converts each emotion variable into ranks

        RANK() OVER (PARTITION BY test ORDER BY y)
        + (COUNT(*) OVER (PARTITION BY test, y) - 1) / 2.0
        AS rank_y -- this converts each box-office variable into ranks

    FROM long
)

SELECT
    test,
    ROUND(CORR(x, LN(y))::numeric, 3) AS pearson_r, -- this calculates Pearson using log-transformed box office
    ROUND(CORR(rank_x, rank_y)::numeric, 3) AS spearman_rho, -- this calculates Spearman
    COUNT(*) AS n -- this counts movies used in each test
FROM ranked
GROUP BY test
ORDER BY test;



-- SQ3 Q1: Positive expert emotion vs worldwide box office - Pearson - Nuria

WITH data AS (
    SELECT
        movie_id,
        expert_posemo AS emotion,
        LN(worldwide_box_office) AS box_office -- this log-transforms worldwide revenue
    FROM public.movie_emotion_analysis
    WHERE expert_posemo IS NOT NULL -- this removes missing expert emotion values
    AND worldwide_box_office > 0 -- this keeps positive revenue values
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)
        -- this removes emotion outliers using 1.5 x IQR

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this removes box-office outliers using 1.5 x IQR
)

SELECT
    CORR(emotion, box_office) AS expert_positive_worldwide, -- this calculates Pearson
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM filtered;



-- SQ3 Q2: Positive expert emotion vs domestic box office - Pearson - Nuria

WITH data AS (
    SELECT
        movie_id,
        expert_posemo AS emotion,
        LN(domestic_box_office) AS box_office -- this log-transforms domestic revenue
    FROM public.movie_emotion_analysis
    WHERE expert_posemo IS NOT NULL
    AND domestic_box_office > 0
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)
        -- this removes emotion outliers

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this removes box-office outliers
)

SELECT
    CORR(emotion, box_office) AS expert_positive_domestic, -- this calculates Pearson
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM filtered;



-- SQ3 Q3: Positive expert emotion vs opening weekend box office - Pearson - Nuria

WITH data AS (
    SELECT
        movie_id,
        expert_posemo AS emotion,
        LN(opening_weekend) AS box_office -- this log-transforms opening-weekend revenue
    FROM public.movie_emotion_analysis
    WHERE expert_posemo IS NOT NULL
    AND opening_weekend > 0
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
)

SELECT
    CORR(emotion, box_office) AS expert_positive_opening, -- this calculates Pearson
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM filtered;



-- SQ3 Q1: Positive expert emotion vs worldwide box office - Spearman - Nuria

WITH data AS (
    SELECT
        movie_id,
        expert_posemo AS emotion,
        LN(worldwide_box_office) AS box_office
    FROM public.movie_emotion_analysis
    WHERE expert_posemo IS NOT NULL
    AND worldwide_box_office > 0
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
),

ranked AS (
    SELECT
        movie_id,

        RANK() OVER (ORDER BY emotion)
        + (COUNT(*) OVER (PARTITION BY emotion) - 1) / 2.0
        AS rank_emotion, -- this converts expert emotion into ranks

        RANK() OVER (ORDER BY box_office)
        + (COUNT(*) OVER (PARTITION BY box_office) - 1) / 2.0
        AS rank_box -- this converts box office into ranks

    FROM filtered
)

SELECT
    CORR(rank_emotion, rank_box) AS spearman_expert_positive_worldwide, -- this calculates Spearman
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM ranked;



-- SQ3 Q2: Positive expert emotion vs domestic box office - Spearman - Nuria

WITH data AS (
    SELECT
        movie_id,
        expert_posemo AS emotion,
        LN(domestic_box_office) AS box_office
    FROM public.movie_emotion_analysis
    WHERE expert_posemo IS NOT NULL
    AND domestic_box_office > 0
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
),

ranked AS (
    SELECT
        movie_id,

        RANK() OVER (ORDER BY emotion)
        + (COUNT(*) OVER (PARTITION BY emotion) - 1) / 2.0
        AS rank_emotion,

        RANK() OVER (ORDER BY box_office)
        + (COUNT(*) OVER (PARTITION BY box_office) - 1) / 2.0
        AS rank_box

    FROM filtered
)

SELECT
    CORR(rank_emotion, rank_box) AS spearman_expert_positive_domestic, -- this calculates Spearman
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM ranked;



-- SQ3 Q3: Positive expert emotion vs opening weekend box office - Spearman - Nuria

WITH data AS (
    SELECT
        movie_id,
        expert_posemo AS emotion,
        LN(opening_weekend) AS box_office
    FROM public.movie_emotion_analysis
    WHERE expert_posemo IS NOT NULL
    AND opening_weekend > 0
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY emotion) AS emotion_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY emotion) AS emotion_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.emotion BETWEEN
        b.emotion_q1 - 1.5 * (b.emotion_q3 - b.emotion_q1)
        AND
        b.emotion_q3 + 1.5 * (b.emotion_q3 - b.emotion_q1)

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
),

ranked AS (
    SELECT
        movie_id,

        RANK() OVER (ORDER BY emotion)
        + (COUNT(*) OVER (PARTITION BY emotion) - 1) / 2.0
        AS rank_emotion,

        RANK() OVER (ORDER BY box_office)
        + (COUNT(*) OVER (PARTITION BY box_office) - 1) / 2.0
        AS rank_box

    FROM filtered
)

SELECT
    CORR(rank_emotion, rank_box) AS spearman_expert_positive_opening, -- this calculates Spearman
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM ranked;

-- SQ4 Q1: Positive consumer emotion vs positive expert emotion in relation to worldwide box office - Pearson - Alexandra

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS avg_consumer_posemo -- this averages positive consumer emotion per movie
    FROM public.consumer_review
    GROUP BY movie_id
),

expert_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS avg_expert_posemo -- this averages positive expert emotion per movie
    FROM public.expert_review
    GROUP BY movie_id
),

data AS (
    SELECT
        s.movie_id,
        c.avg_consumer_posemo AS consumer_emotion,
        e.avg_expert_posemo AS expert_emotion,
        LN(s.worldwide_box_office) AS box_office -- this log-transforms worldwide revenue
    FROM public.sales s

    JOIN consumer_avg c
        ON s.movie_id = c.movie_id -- this connects consumer emotion to sales

    JOIN expert_avg e
        ON s.movie_id = e.movie_id -- this connects expert emotion to sales

    WHERE s.worldwide_box_office > 0
    AND c.avg_consumer_posemo IS NOT NULL
    AND e.avg_expert_posemo IS NOT NULL -- this keeps only movies available for both sources
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_emotion) AS consumer_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_emotion) AS consumer_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_emotion) AS expert_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_emotion) AS expert_q3,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.consumer_emotion BETWEEN
        b.consumer_q1 - 1.5 * (b.consumer_q3 - b.consumer_q1)
        AND
        b.consumer_q3 + 1.5 * (b.consumer_q3 - b.consumer_q1)
        -- this removes consumer-emotion outliers

    AND d.expert_emotion BETWEEN
        b.expert_q1 - 1.5 * (b.expert_q3 - b.expert_q1)
        AND
        b.expert_q3 + 1.5 * (b.expert_q3 - b.expert_q1)
        -- this removes expert-emotion outliers

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this removes box-office outliers
)

SELECT
    CORR(consumer_emotion, box_office) AS consumer_pearson, -- consumer positive emotion correlation
    CORR(expert_emotion, box_office) AS expert_pearson, -- expert positive emotion correlation
    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM filtered;

-- SQ4 Q2: Negative consumer emotion vs negative expert emotion in relation to worldwide box office - Zein

SELECT
    CORR(c.negemo, LN(s.worldwide_box_office)) AS consumer_pearson, -- this calculates the Pearson correlation for consumer negative emotion
    CORR(e.negemo, LN(s.worldwide_box_office)) AS expert_pearson, -- this calculates the Pearson correlation for expert negative emotion
    COUNT(*) AS movies_used -- this counts the movies used in the comparison

FROM public.sales s

JOIN (
    SELECT
        movie_id,
        AVG(negemo) AS negemo -- this averages consumer negative emotion per movie
    FROM public.consumer_review
    GROUP BY movie_id -- this changes consumer review-level data into one row per movie
) c
    ON s.movie_id = c.movie_id -- this connects consumer negative emotion to sales

JOIN (
    SELECT
        movie_id,
        AVG(negemo) AS negemo -- this averages expert negative emotion per movie
    FROM public.expert_review
    GROUP BY movie_id -- this changes expert review-level data into one row per movie
) e
    ON s.movie_id = e.movie_id -- this connects expert negative emotion to sales

WHERE s.worldwide_box_office > 0 -- this removes zero or negative revenue before LN()
  AND c.negemo IS NOT NULL -- this removes movies with missing consumer negative emotion
  AND e.negemo IS NOT NULL; -- this removes movies with missing expert negative emotion

-- SQ4 Q3: Consumer tone vs expert tone in relation to worldwide box office - Nuria

SELECT
    CORR(c.tone, LN(s.worldwide_box_office)) AS consumer_pearson, -- this calculates the Pearson correlation for consumer tone
    CORR(e.tone, LN(s.worldwide_box_office)) AS expert_pearson, -- this calculates the Pearson correlation for expert tone
    COUNT(*) AS movies_used -- this counts the movies used in the comparison

FROM public.sales s

JOIN (
    SELECT
        movie_id,
        AVG(tone) AS tone -- this averages consumer tone per movie
    FROM public.consumer_review
    GROUP BY movie_id -- this changes consumer review-level data into one row per movie
) c
    ON s.movie_id = c.movie_id -- this connects consumer tone to sales

JOIN (
    SELECT
        movie_id,
        AVG(tone) AS tone -- this averages expert tone per movie
    FROM public.expert_review
    GROUP BY movie_id -- this changes expert review-level data into one row per movie
) e
    ON s.movie_id = e.movie_id -- this connects expert tone to sales

WHERE s.worldwide_box_office > 0 -- this removes zero or negative revenue before LN()
  AND c.tone IS NOT NULL -- this removes movies with missing consumer tone
  AND e.tone IS NOT NULL; -- this removes movies with missing expert tone


-- All emotion correlations: Consumer and expert emotions vs worldwide box office - Pearson - Alexandra, Zein, Nuria
-- Outlier removal using 1.5 x IQR - Alexandra, Zein, Nuria

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS consumer_posemo, -- this averages consumer positive emotion
        AVG(negemo) AS consumer_negemo, -- this averages consumer negative emotion
        AVG(tone) AS consumer_tone, -- this averages consumer tone
        AVG(anx) AS consumer_anx, -- this averages consumer anxiety
        AVG(anger) AS consumer_anger, -- this averages consumer anger
        AVG(sad) AS consumer_sad -- this averages consumer sadness
    FROM public.consumer_review
    GROUP BY movie_id -- this changes review-level data into movie-level data
),

expert_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS expert_posemo, -- this averages expert positive emotion
        AVG(negemo) AS expert_negemo, -- this averages expert negative emotion
        AVG(tone) AS expert_tone, -- this averages expert tone
        AVG(anx) AS expert_anx, -- this averages expert anxiety
        AVG(anger) AS expert_anger, -- this averages expert anger
        AVG(sad) AS expert_sad -- this averages expert sadness
    FROM public.expert_review
    GROUP BY movie_id -- this changes review-level data into movie-level data
),

data AS (
    SELECT
        s.movie_id,
        LN(s.worldwide_box_office) AS box_office, -- this log-transforms worldwide revenue

        c.consumer_posemo,
        c.consumer_negemo,
        c.consumer_tone,
        c.consumer_anx,
        c.consumer_anger,
        c.consumer_sad,

        e.expert_posemo,
        e.expert_negemo,
        e.expert_tone,
        e.expert_anx,
        e.expert_anger,
        e.expert_sad

    FROM public.sales s

    JOIN consumer_avg c
        ON s.movie_id = c.movie_id -- this connects consumer emotions to sales

    JOIN expert_avg e
        ON s.movie_id = e.movie_id -- this connects expert emotions to sales

    WHERE s.worldwide_box_office > 0 -- this removes invalid values before LN()

    AND c.consumer_posemo IS NOT NULL
    AND c.consumer_negemo IS NOT NULL
    AND c.consumer_tone IS NOT NULL
    AND c.consumer_anx IS NOT NULL
    AND c.consumer_anger IS NOT NULL
    AND c.consumer_sad IS NOT NULL

    AND e.expert_posemo IS NOT NULL
    AND e.expert_negemo IS NOT NULL
    AND e.expert_tone IS NOT NULL
    AND e.expert_anx IS NOT NULL
    AND e.expert_anger IS NOT NULL
    AND e.expert_sad IS NOT NULL
    -- this keeps a common complete sample for all emotion variables
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_posemo) AS consumer_posemo_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_posemo) AS consumer_posemo_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_negemo) AS consumer_negemo_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_negemo) AS consumer_negemo_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_tone) AS consumer_tone_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_tone) AS consumer_tone_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_anx) AS consumer_anx_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_anx) AS consumer_anx_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_anger) AS consumer_anger_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_anger) AS consumer_anger_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_sad) AS consumer_sad_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_sad) AS consumer_sad_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_posemo) AS expert_posemo_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_posemo) AS expert_posemo_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_negemo) AS expert_negemo_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_negemo) AS expert_negemo_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_tone) AS expert_tone_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_tone) AS expert_tone_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_anx) AS expert_anx_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_anx) AS expert_anx_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_anger) AS expert_anger_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_anger) AS expert_anger_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_sad) AS expert_sad_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_sad) AS expert_sad_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3
    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.consumer_posemo BETWEEN
        b.consumer_posemo_q1 - 1.5 * (b.consumer_posemo_q3 - b.consumer_posemo_q1)
        AND
        b.consumer_posemo_q3 + 1.5 * (b.consumer_posemo_q3 - b.consumer_posemo_q1)

    AND d.consumer_negemo BETWEEN
        b.consumer_negemo_q1 - 1.5 * (b.consumer_negemo_q3 - b.consumer_negemo_q1)
        AND
        b.consumer_negemo_q3 + 1.5 * (b.consumer_negemo_q3 - b.consumer_negemo_q1)

    AND d.consumer_tone BETWEEN
        b.consumer_tone_q1 - 1.5 * (b.consumer_tone_q3 - b.consumer_tone_q1)
        AND
        b.consumer_tone_q3 + 1.5 * (b.consumer_tone_q3 - b.consumer_tone_q1)

    AND d.consumer_anx BETWEEN
        b.consumer_anx_q1 - 1.5 * (b.consumer_anx_q3 - b.consumer_anx_q1)
        AND
        b.consumer_anx_q3 + 1.5 * (b.consumer_anx_q3 - b.consumer_anx_q1)

    AND d.consumer_anger BETWEEN
        b.consumer_anger_q1 - 1.5 * (b.consumer_anger_q3 - b.consumer_anger_q1)
        AND
        b.consumer_anger_q3 + 1.5 * (b.consumer_anger_q3 - b.consumer_anger_q1)

    AND d.consumer_sad BETWEEN
        b.consumer_sad_q1 - 1.5 * (b.consumer_sad_q3 - b.consumer_sad_q1)
        AND
        b.consumer_sad_q3 + 1.5 * (b.consumer_sad_q3 - b.consumer_sad_q1)

    AND d.expert_posemo BETWEEN
        b.expert_posemo_q1 - 1.5 * (b.expert_posemo_q3 - b.expert_posemo_q1)
        AND
        b.expert_posemo_q3 + 1.5 * (b.expert_posemo_q3 - b.expert_posemo_q1)

    AND d.expert_negemo BETWEEN
        b.expert_negemo_q1 - 1.5 * (b.expert_negemo_q3 - b.expert_negemo_q1)
        AND
        b.expert_negemo_q3 + 1.5 * (b.expert_negemo_q3 - b.expert_negemo_q1)

    AND d.expert_tone BETWEEN
        b.expert_tone_q1 - 1.5 * (b.expert_tone_q3 - b.expert_tone_q1)
        AND
        b.expert_tone_q3 + 1.5 * (b.expert_tone_q3 - b.expert_tone_q1)

    AND d.expert_anx BETWEEN
        b.expert_anx_q1 - 1.5 * (b.expert_anx_q3 - b.expert_anx_q1)
        AND
        b.expert_anx_q3 + 1.5 * (b.expert_anx_q3 - b.expert_anx_q1)

    AND d.expert_anger BETWEEN
        b.expert_anger_q1 - 1.5 * (b.expert_anger_q3 - b.expert_anger_q1)
        AND
        b.expert_anger_q3 + 1.5 * (b.expert_anger_q3 - b.expert_anger_q1)

    AND d.expert_sad BETWEEN
        b.expert_sad_q1 - 1.5 * (b.expert_sad_q3 - b.expert_sad_q1)
        AND
        b.expert_sad_q3 + 1.5 * (b.expert_sad_q3 - b.expert_sad_q1)

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this applies the 1.5 x IQR outlier rule to the common sample
)

SELECT
    CORR(consumer_posemo, box_office) AS consumer_posemo_pearson, -- positive consumer emotion vs worldwide box office
    CORR(consumer_negemo, box_office) AS consumer_negemo_pearson, -- negative consumer emotion vs worldwide box office
    CORR(consumer_tone, box_office) AS consumer_tone_pearson,
    CORR(consumer_anx, box_office) AS consumer_anx_pearson,
    CORR(consumer_anger, box_office) AS consumer_anger_pearson,
    CORR(consumer_sad, box_office) AS consumer_sad_pearson,

    CORR(expert_posemo, box_office) AS expert_posemo_pearson, -- positive expert emotion vs worldwide box office
    CORR(expert_negemo, box_office) AS expert_negemo_pearson, -- negative expert emotion vs worldwide box office
    CORR(expert_tone, box_office) AS expert_tone_pearson,
    CORR(expert_anx, box_office) AS expert_anx_pearson,
    CORR(expert_anger, box_office) AS expert_anger_pearson,
    CORR(expert_sad, box_office) AS expert_sad_pearson,

    (SELECT COUNT(*) FROM data) AS movies_before,
    COUNT(*) AS movies_used,
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed
FROM filtered;



-- All emotion correlations: Consumer and expert emotions vs worldwide box office - Spearman - Alexandra, Zein, Nuria
-- Outlier removal using 1.5 x IQR - Alexandra, Zein, Nuria

WITH consumer_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS consumer_posemo,
        AVG(negemo) AS consumer_negemo,
        AVG(tone) AS consumer_tone,
        AVG(anx) AS consumer_anx,
        AVG(anger) AS consumer_anger,
        AVG(sad) AS consumer_sad
    FROM public.consumer_review
    GROUP BY movie_id -- this changes consumer reviews into one row per movie
),

expert_avg AS (
    SELECT
        movie_id,
        AVG(posemo) AS expert_posemo,
        AVG(negemo) AS expert_negemo,
        AVG(tone) AS expert_tone,
        AVG(anx) AS expert_anx,
        AVG(anger) AS expert_anger,
        AVG(sad) AS expert_sad
    FROM public.expert_review
    GROUP BY movie_id -- this changes expert reviews into one row per movie
),

data AS (
    SELECT
        s.movie_id,
        LN(s.worldwide_box_office) AS box_office, -- this log-transforms worldwide revenue

        c.consumer_posemo,
        c.consumer_negemo,
        c.consumer_tone,
        c.consumer_anx,
        c.consumer_anger,
        c.consumer_sad,

        e.expert_posemo,
        e.expert_negemo,
        e.expert_tone,
        e.expert_anx,
        e.expert_anger,
        e.expert_sad

    FROM public.sales s

    JOIN consumer_avg c
        ON s.movie_id = c.movie_id -- this connects consumer emotions to sales

    JOIN expert_avg e
        ON s.movie_id = e.movie_id -- this connects expert emotions to sales

    WHERE s.worldwide_box_office > 0

    AND c.consumer_posemo IS NOT NULL
    AND c.consumer_negemo IS NOT NULL
    AND c.consumer_tone IS NOT NULL
    AND c.consumer_anx IS NOT NULL
    AND c.consumer_anger IS NOT NULL
    AND c.consumer_sad IS NOT NULL

    AND e.expert_posemo IS NOT NULL
    AND e.expert_negemo IS NOT NULL
    AND e.expert_tone IS NOT NULL
    AND e.expert_anx IS NOT NULL
    AND e.expert_anger IS NOT NULL
    AND e.expert_sad IS NOT NULL
    -- this keeps the same complete sample for all emotions
),

bounds AS (
    SELECT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_posemo) AS consumer_posemo_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_posemo) AS consumer_posemo_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_negemo) AS consumer_negemo_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_negemo) AS consumer_negemo_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_tone) AS consumer_tone_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_tone) AS consumer_tone_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_anx) AS consumer_anx_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_anx) AS consumer_anx_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_anger) AS consumer_anger_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_anger) AS consumer_anger_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY consumer_sad) AS consumer_sad_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY consumer_sad) AS consumer_sad_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_posemo) AS expert_posemo_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_posemo) AS expert_posemo_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_negemo) AS expert_negemo_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_negemo) AS expert_negemo_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_tone) AS expert_tone_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_tone) AS expert_tone_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_anx) AS expert_anx_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_anx) AS expert_anx_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_anger) AS expert_anger_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_anger) AS expert_anger_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY expert_sad) AS expert_sad_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY expert_sad) AS expert_sad_q3,

        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY box_office) AS box_q1,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY box_office) AS box_q3

    FROM data
),

filtered AS (
    SELECT d.*
    FROM data d
    CROSS JOIN bounds b

    WHERE d.consumer_posemo BETWEEN
        b.consumer_posemo_q1 - 1.5 * (b.consumer_posemo_q3 - b.consumer_posemo_q1)
        AND
        b.consumer_posemo_q3 + 1.5 * (b.consumer_posemo_q3 - b.consumer_posemo_q1)

    AND d.consumer_negemo BETWEEN
        b.consumer_negemo_q1 - 1.5 * (b.consumer_negemo_q3 - b.consumer_negemo_q1)
        AND
        b.consumer_negemo_q3 + 1.5 * (b.consumer_negemo_q3 - b.consumer_negemo_q1)

    AND d.consumer_tone BETWEEN
        b.consumer_tone_q1 - 1.5 * (b.consumer_tone_q3 - b.consumer_tone_q1)
        AND
        b.consumer_tone_q3 + 1.5 * (b.consumer_tone_q3 - b.consumer_tone_q1)

    AND d.consumer_anx BETWEEN
        b.consumer_anx_q1 - 1.5 * (b.consumer_anx_q3 - b.consumer_anx_q1)
        AND
        b.consumer_anx_q3 + 1.5 * (b.consumer_anx_q3 - b.consumer_anx_q1)

    AND d.consumer_anger BETWEEN
        b.consumer_anger_q1 - 1.5 * (b.consumer_anger_q3 - b.consumer_anger_q1)
        AND
        b.consumer_anger_q3 + 1.5 * (b.consumer_anger_q3 - b.consumer_anger_q1)

    AND d.consumer_sad BETWEEN
        b.consumer_sad_q1 - 1.5 * (b.consumer_sad_q3 - b.consumer_sad_q1)
        AND
        b.consumer_sad_q3 + 1.5 * (b.consumer_sad_q3 - b.consumer_sad_q1)

    AND d.expert_posemo BETWEEN
        b.expert_posemo_q1 - 1.5 * (b.expert_posemo_q3 - b.expert_posemo_q1)
        AND
        b.expert_posemo_q3 + 1.5 * (b.expert_posemo_q3 - b.expert_posemo_q1)

    AND d.expert_negemo BETWEEN
        b.expert_negemo_q1 - 1.5 * (b.expert_negemo_q3 - b.expert_negemo_q1)
        AND
        b.expert_negemo_q3 + 1.5 * (b.expert_negemo_q3 - b.expert_negemo_q1)

    AND d.expert_tone BETWEEN
        b.expert_tone_q1 - 1.5 * (b.expert_tone_q3 - b.expert_tone_q1)
        AND
        b.expert_tone_q3 + 1.5 * (b.expert_tone_q3 - b.expert_tone_q1)

    AND d.expert_anx BETWEEN
        b.expert_anx_q1 - 1.5 * (b.expert_anx_q3 - b.expert_anx_q1)
        AND
        b.expert_anx_q3 + 1.5 * (b.expert_anx_q3 - b.expert_anx_q1)

    AND d.expert_anger BETWEEN
        b.expert_anger_q1 - 1.5 * (b.expert_anger_q3 - b.expert_anger_q1)
        AND
        b.expert_anger_q3 + 1.5 * (b.expert_anger_q3 - b.expert_anger_q1)

    AND d.expert_sad BETWEEN
        b.expert_sad_q1 - 1.5 * (b.expert_sad_q3 - b.expert_sad_q1)
        AND
        b.expert_sad_q3 + 1.5 * (b.expert_sad_q3 - b.expert_sad_q1)

    AND d.box_office BETWEEN
        b.box_q1 - 1.5 * (b.box_q3 - b.box_q1)
        AND
        b.box_q3 + 1.5 * (b.box_q3 - b.box_q1)
        -- this applies the same IQR outlier treatment before ranking
),

ranked AS (
    SELECT
        movie_id,

        RANK() OVER (ORDER BY box_office)
        + (COUNT(*) OVER (PARTITION BY box_office) - 1) / 2.0
        AS box_office_rank, -- this converts worldwide box office into ranks

        RANK() OVER (ORDER BY consumer_posemo)
        + (COUNT(*) OVER (PARTITION BY consumer_posemo) - 1) / 2.0
        AS consumer_posemo_rank, -- this converts consumer positive emotion into ranks

        RANK() OVER (ORDER BY consumer_negemo)
        + (COUNT(*) OVER (PARTITION BY consumer_negemo) - 1) / 2.0
        AS consumer_negemo_rank,

        RANK() OVER (ORDER BY consumer_tone)
        + (COUNT(*) OVER (PARTITION BY consumer_tone) - 1) / 2.0
        AS consumer_tone_rank,

        RANK() OVER (ORDER BY consumer_anx)
        + (COUNT(*) OVER (PARTITION BY consumer_anx) - 1) / 2.0
        AS consumer_anx_rank,

        RANK() OVER (ORDER BY consumer_anger)
        + (COUNT(*) OVER (PARTITION BY consumer_anger) - 1) / 2.0
        AS consumer_anger_rank,

        RANK() OVER (ORDER BY consumer_sad)
        + (COUNT(*) OVER (PARTITION BY consumer_sad) - 1) / 2.0
        AS consumer_sad_rank,

        RANK() OVER (ORDER BY expert_posemo)
        + (COUNT(*) OVER (PARTITION BY expert_posemo) - 1) / 2.0
        AS expert_posemo_rank, -- this converts expert positive emotion into ranks

        RANK() OVER (ORDER BY expert_negemo)
        + (COUNT(*) OVER (PARTITION BY expert_negemo) - 1) / 2.0
        AS expert_negemo_rank,

        RANK() OVER (ORDER BY expert_tone)
        + (COUNT(*) OVER (PARTITION BY expert_tone) - 1) / 2.0
        AS expert_tone_rank,

        RANK() OVER (ORDER BY expert_anx)
        + (COUNT(*) OVER (PARTITION BY expert_anx) - 1) / 2.0
        AS expert_anx_rank,

        RANK() OVER (ORDER BY expert_anger)
        + (COUNT(*) OVER (PARTITION BY expert_anger) - 1) / 2.0
        AS expert_anger_rank,

        RANK() OVER (ORDER BY expert_sad)
        + (COUNT(*) OVER (PARTITION BY expert_sad) - 1) / 2.0
        AS expert_sad_rank

    FROM filtered
)

SELECT
    CORR(consumer_posemo_rank, box_office_rank) AS consumer_posemo_spearman, -- consumer positive emotion vs box office
    CORR(consumer_negemo_rank, box_office_rank) AS consumer_negemo_spearman, -- consumer negative emotion vs box office
    CORR(consumer_tone_rank, box_office_rank) AS consumer_tone_spearman,
    CORR(consumer_anx_rank, box_office_rank) AS consumer_anx_spearman,
    CORR(consumer_anger_rank, box_office_rank) AS consumer_anger_spearman,
    CORR(consumer_sad_rank, box_office_rank) AS consumer_sad_spearman,

    CORR(expert_posemo_rank, box_office_rank) AS expert_posemo_spearman, -- expert positive emotion vs box office
    CORR(expert_negemo_rank, box_office_rank) AS expert_negemo_spearman, -- expert negative emotion vs box office
    CORR(expert_tone_rank, box_office_rank) AS expert_tone_spearman,
    CORR(expert_anx_rank, box_office_rank) AS expert_anx_spearman,
    CORR(expert_anger_rank, box_office_rank) AS expert_anger_spearman,
    CORR(expert_sad_rank, box_office_rank) AS expert_sad_spearman,

    (SELECT COUNT(*) FROM data) AS movies_before, -- this counts movies before outlier removal
    COUNT(*) AS movies_used, -- this counts movies remaining after filtering
    (SELECT COUNT(*) FROM data) - COUNT(*) AS outliers_removed -- this counts removed outliers

FROM ranked;
