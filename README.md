# Data Cleaning

Notebook: `ALL_cleaned_FINAL.ipynb`. It reads the four source Excel files, cleans them with pandas and exports the ten tables of the final ERD as CSV files. Every decision is explicit, and nothing is deleted when it can be set to NULL instead.

| Source file | Raw rows | Content |
| --- | --- | --- |
| `metaClean43Brightspace.xlsx` | 11,364 | Movie description from Metacritic |
| `sales.xlsx` | 30,612 | Budget and box office from the-numbers.com |
| `ExpertReviewsClean43LIWC.xlsx` | 238,973 | Critic reviews with LIWC scores |
| `UserReviewsClean43LIWC.xlsx` | 319,662 | Audience reviews with LIWC scores |

| Table | Final rows |
| --- | --- |
| `movie` | 11,364 |
| `sales` | 8,377 |
| `genre` / `movie_genre` | 27 / 27,051 |
| `actor` / `movie_cast` | 24,855 / 48,280 |
| `award` / `movie_award` | 6,407 / 6,409 |
| `expert_review` | 238,944 |
| `consumer_review` | 316,125 |

The notebook `TEAM_MASTER_CLEANING_AND_POSTGRES.ipynb` applies the same cleaning and then creates and loads the PostgreSQL tables directly.

## Code

### Step 0 – Libraries

The notebook uses `pandas` and `numpy` for tables, `re` and `unicodedata` for text cleaning, and `ftfy` to repair broken encoding.

```python
import pandas as pd
import numpy as np
import re
import unicodedata
from ftfy import fix_text
from urllib.parse import urlparse, unquote
from pathlib import Path

pd.set_option("display.max_columns", None)
```

### Step 1 – Load the four source files

The four untouched Excel files are read into DataFrames. The row counts printed here are the raw counts: MOVIE 11,364, SALES 30,612, EXPERT 238,973, CONSUMER 319,662.

```python
meta_raw = pd.read_excel("metaClean43Brightspace.xlsx")
sales_raw = pd.read_excel("sales.xlsx")
expert_raw = pd.read_excel("ExpertReviewsClean43LIWC.xlsx")
consumer_raw = pd.read_excel("UserReviewsClean43LIWC.xlsx")

print("MOVIE:", len(meta_raw))
print("SALES:", len(sales_raw))
print("EXPERT:", len(expert_raw))
print("CONSUMER:", len(consumer_raw))
```

### Step 2 – Helper functions

Small functions reused in every step: `clean_text` and `clean_review_text` repair encoding and turn words such as `none` or `nan` into real NULLs, `title_from_url` recovers a missing title from the URL, `title_key` builds the normalised key used to match sales to movies (no accents, punctuation or capitals), and the others convert numbers, money and dates safely.

```python
NULL_WORDS = {"", "none", "null", "nan", "n/a", "na"}


def clean_text(value):
    if pd.isna(value):
        return pd.NA

    value = fix_text(str(value))
    value = re.sub(
        r"[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]",
        "",
        value
    )
    value = value.strip()

    if value.casefold() in NULL_WORDS:
        return pd.NA

    return value


def clean_review_text(value):
    if pd.isna(value):
        return pd.NA

    value = fix_text(str(value))

    # Replace line breaks/control characters with spaces
    value = re.sub(r"[\x00-\x1F\x7F]+", " ", value)

    # Collapse repeated spaces
    value = re.sub(r"\s+", " ", value).strip()

    if value.casefold() in NULL_WORDS:
        return pd.NA

    return value


def title_from_url(url):
    if pd.isna(url):
        return pd.NA

    path = unquote(urlparse(str(url)).path)

    if "/movie/" not in path.lower():
        return pd.NA

    lower = path.lower()
    position = lower.find("/movie/")

    slug = path[
        position + len("/movie/"):
    ].strip("/")

    if not slug:
        return pd.NA

    return slug.replace("-", " ")


def reorder_article(value):
    value = clean_text(value)

    if pd.isna(value):
        return pd.NA

    match = re.match(
        r"^(.*),\s*(The|A|An)$",
        str(value),
        flags=re.I
    )

    if match:
        return f"{match.group(2)} {match.group(1)}"

    return value


def title_key(value):
    """
    Matching only.

    Example:
    Spider-Man: Homecoming
    Spider Man Homecoming

    become the same matching key.
    """

    value = reorder_article(value)

    if pd.isna(value):
        return pd.NA

    value = unicodedata.normalize(
        "NFKD",
        str(value)
    )

    value = "".join(
        character
        for character in value
        if not unicodedata.combining(character)
    )

    value = value.casefold()

    value = re.sub(
        r"[^a-z0-9]",
        "",
        value
    )

    return value if value else pd.NA


def to_nullable_int(series):
    numbers = pd.to_numeric(
        series,
        errors="coerce"
    )

    # Do not silently round decimal values
    decimal_values = (
        numbers.notna()
        & ((numbers % 1).abs() > 1e-12)
    )

    numbers = numbers.mask(decimal_values)

    return numbers.astype("Int64")


def clean_money(series):
    series = series.astype("string")

    series = series.str.replace(
        r"[$,\s]",
        "",
        regex=True
    )

    return pd.to_numeric(
        series,
        errors="coerce"
    )


def parse_review_dates(series):

    dates = (
        series
        .astype("string")
        .str.strip()
        .str.strip("'\"")
        .str.strip()
    )

    dates = dates.mask(
        dates.str.casefold().isin(NULL_WORDS),
        pd.NA
    )

    parsed = pd.to_datetime(
        dates,
        format="%b %d, %Y",
        errors="coerce"
    )

    # fallback for any other legitimate format
    missing = parsed.isna() & dates.notna()

    if missing.any():

        parsed.loc[missing] = pd.to_datetime(
            dates.loc[missing],
            format="mixed",
            errors="coerce"
        )

    return parsed
```

### Step 3 – MOVIE

Each movie gets a stable `movie_id` from the original Metacritic row order. Text is repaired, ratings are standardised (`PG--13` becomes `PG-13`, `NR` becomes `Not Rated`), confirmed typos are fixed by hand, and one confirmed wrong runtime (The Tenants, 31 minutes) is set to NULL instead of inventing a value.

```python
meta = meta_raw.copy()

# Stable ID based on original Metacritic row order
meta.insert(
    0,
    "movie_id",
    range(1, len(meta) + 1)
)

movie = meta.rename(
    columns={
        "url": "metacritic_url",
        "RelDate": "release_date"
    }
).copy()


# ------------------------------------------------------------
# TEXT CLEANING
# ------------------------------------------------------------

text_columns = [
    "metacritic_url",
    "title",
    "studio",
    "rating",
    "summary",
    "director"
]

for col in text_columns:
    movie[col] = movie[col].apply(clean_text)


# ------------------------------------------------------------
# RECOVER MISSING TITLES
# ------------------------------------------------------------

missing_title = movie["title"].isna()

movie.loc[
    missing_title,
    "title"
] = movie.loc[
    missing_title,
    "metacritic_url"
].apply(title_from_url)


# ------------------------------------------------------------
# CONFIRMED TITLE FIXES
# ------------------------------------------------------------

movie["title"] = movie["title"].replace({

    "Cet amour-lÃ":
        "Cet amour-là",

    "Caterina va in cittÃ":
        "Caterina va in città"
})


# ------------------------------------------------------------
# CONFIRMED DIRECTOR FIXES
# ------------------------------------------------------------

movie["director"] = movie["director"].replace({

    "Brian A Miller":
        "Brian A. Miller",

    "Takashi  Miike":
        "Takashi Miike"
})


# ------------------------------------------------------------
# RATINGS
# ------------------------------------------------------------

movie["rating"] = (
    movie["rating"]
    .astype("string")
    .str.replace(
        r"^\s*\|\s*",
        "",
        regex=True
    )
    .str.strip()
    .replace("", pd.NA)
)

movie["rating"] = movie["rating"].replace({

    "PG--13": "PG-13",

    "PG-13`": "PG-13",

    "NR": "Not Rated"
})


# ------------------------------------------------------------
# RUNTIME
# ------------------------------------------------------------

movie["runtime"] = to_nullable_int(
    movie["runtime"]
)

# Confirmed incorrect runtime:
# do NOT invent a replacement
movie.loc[
    movie["title"].eq("The Tenants")
    & movie["runtime"].eq(31),
    "runtime"
] = pd.NA


# ------------------------------------------------------------
# METASCORE
# ------------------------------------------------------------

movie["metascore"] = to_nullable_int(
    movie["metascore"]
)


# ------------------------------------------------------------
# RELEASE DATE
# ------------------------------------------------------------

movie["release_date"] = pd.to_datetime(
    movie["release_date"],
    format="mixed",
    errors="coerce"
)


# ------------------------------------------------------------
# SALES ATTRIBUTES
# ------------------------------------------------------------

# Filled after SALES matching
movie["keywords"] = pd.NA
movie["creative_type"] = pd.NA


# ------------------------------------------------------------
# FINAL MOVIE
# ------------------------------------------------------------

movie = movie[[
    "movie_id",
    "metacritic_url",
    "title",
    "studio",
    "rating",
    "summary",
    "runtime",
    "director",
    "metascore",
    "release_date",
    "keywords",
    "creative_type"
]].copy()


print("MOVIE rows:", len(movie))
print(
    "Missing runtimes:",
    movie["runtime"].isna().sum()
)
print(
    "Invalid runtimes:",
    (movie["runtime"].dropna() <= 0).sum()
)
print(
    "Invalid metascores:",
    (
        ~movie["metascore"]
        .dropna()
        .between(0, 100)
    ).sum()
)
```

### Step 4 – GENRE and MOVIE_GENRE

Genres are stored as comma-separated text in the source. They are split into one row per value, de-duplicated, and linked to movies through the junction table `movie_genre` (normalisation). Result: 27 genres and 27,051 links.

```python
genre_split = meta[
    ["movie_id", "genre"]
].copy()

genre_split["genre_name"] = (
    genre_split["genre"]
    .apply(clean_text)
    .str.split(",")
)

genre_split = genre_split.explode(
    "genre_name"
)

genre_split["genre_name"] = (
    genre_split["genre_name"]
    .apply(clean_text)
)

genre_split = genre_split.dropna(
    subset=["genre_name"]
)

genre_split = genre_split.drop_duplicates(
    ["movie_id", "genre_name"]
)


genre = pd.DataFrame({
    "genre_name":
        sorted(
            genre_split[
                "genre_name"
            ].unique()
        )
})

genre.insert(
    0,
    "genre_id",
    range(1, len(genre) + 1)
)


movie_genre = (
    genre_split[
        ["movie_id", "genre_name"]
    ]
    .merge(
        genre,
        on="genre_name",
        how="left",
        validate="many_to_one"
    )
    [["movie_id", "genre_id"]]
    .drop_duplicates()
    .reset_index(drop=True)
)


print("GENRE:", len(genre))
print(
    "MOVIE_GENRE:",
    len(movie_genre)
)
```

### Step 5 – ACTOR and MOVIE_CAST

Same idea for the cast. Only confirmed spelling duplicates are merged (for example `Charlotte Lebon` and `Charlotte Le Bon`). `J.R.`/`JR` and `T.I.`/`Ti` stay separate because there was not enough evidence to merge them. Result: 24,855 actors and 48,280 links.

```python
cast_split = meta[
    ["movie_id", "cast"]
].copy()

cast_split["actor_name"] = (
    cast_split["cast"]
    .apply(clean_text)
    .str.split(",")
)

cast_split = cast_split.explode(
    "actor_name"
)

cast_split["actor_name"] = (
    cast_split["actor_name"]
    .apply(clean_text)
)

cast_split = cast_split.dropna(
    subset=["actor_name"]
)


# Confirmed spelling / encoding duplicates
actor_name_fixes = {

    "B.D. Wong":
        "BD Wong",

    "Charlotte Lebon":
        "Charlotte Le Bon",

    "Jin Auyeung":
        "Jin Au-Yeung",

    "LisaGay Hamilton":
        "Lisa Gay Hamilton",

    "Michelle Rodriguez":
        "Michelle Rodríguez",

    "PÃ¥l Sverre Valheim Hagen":
        "Pål Sverre Valheim Hagen"
}

cast_split["actor_name"] = (
    cast_split["actor_name"]
    .replace(actor_name_fixes)
)


# Important:
# J.R. and JR remain separate
# T.I. and Ti remain separate

cast_split = cast_split.drop_duplicates(
    ["movie_id", "actor_name"]
)


actor = pd.DataFrame({
    "actor_name":
        sorted(
            cast_split[
                "actor_name"
            ].unique()
        )
})

actor.insert(
    0,
    "actor_id",
    range(1, len(actor) + 1)
)


movie_cast = (
    cast_split[
        ["movie_id", "actor_name"]
    ]
    .merge(
        actor,
        on="actor_name",
        how="left",
        validate="many_to_one"
    )
    [["movie_id", "actor_id"]]
    .drop_duplicates()
    .reset_index(drop=True)
)


print("ACTOR:", len(actor))
print(
    "MOVIE_CAST:",
    len(movie_cast)
)
```

### Step 6 – AWARD and MOVIE_AWARD

Awards are split and standardised (for example `BestMovie` becomes `Best Movie`). Result: 6,407 awards and 6,409 links.

```python
award_split = meta[
    ["movie_id", "awards"]
].copy()

award_split["award_name"] = (
    award_split["awards"]
    .apply(clean_text)
    .str.split(",")
)

award_split = award_split.explode(
    "award_name"
)

award_split["award_name"] = (
    award_split["award_name"]
    .apply(clean_text)
)

award_split = award_split.dropna(
    subset=["award_name"]
)


def standardize_award(value):

    if pd.isna(value):
        return pd.NA

    value = str(value).strip()

    value = re.sub(
        r"\bBestMovie\b",
        "Best Movie",
        value
    )

    value = re.sub(
        r"\bMostDiscussedMovie\b",
        "Most Discussed Movie",
        value
    )

    value = re.sub(
        r"\bMostSharedMovie\b",
        "Most Shared Movie",
        value
    )

    value = re.sub(
        r"\bMovieof(\d{4})\b",
        r"Movie of \1",
        value
    )

    value = re.sub(
        r"^#\s*(\d+)",
        r"#\1",
        value
    )

    return value


award_split["award_name"] = (
    award_split["award_name"]
    .apply(standardize_award)
)

award_split = award_split.drop_duplicates(
    ["movie_id", "award_name"]
)


award = pd.DataFrame({
    "award_name":
        sorted(
            award_split[
                "award_name"
            ].unique()
        )
})

award.insert(
    0,
    "award_id",
    range(1, len(award) + 1)
)


movie_award = (
    award_split[
        ["movie_id", "award_name"]
    ]
    .merge(
        award,
        on="award_name",
        how="left",
        validate="many_to_one"
    )
    [["movie_id", "award_id"]]
    .drop_duplicates()
    .reset_index(drop=True)
)


print("AWARD:", len(award))
print(
    "MOVIE_AWARD:",
    len(movie_award)
)
```

### Step 7 – SALES: prepare the data

Titles are cleaned, a missing title is recovered from the URL, the match year is taken from `year` (or from the release date only if `year` is missing), the matching key is built, and money columns are converted to numbers.

```python
sales_work = sales_raw.copy()

sales_work = sales_work.reset_index(
    drop=True
)

sales_work["_source_row"] = (
    sales_work.index
)


# ------------------------------------------------------------
# CLEAN TITLES
# ------------------------------------------------------------

sales_work["sales_title"] = (
    sales_work["title"]
    .apply(clean_text)
)


# Recover missing titles using URL
missing_sales_title = (
    sales_work["sales_title"]
    .isna()
)

sales_work.loc[
    missing_sales_title,
    "sales_title"
] = sales_work.loc[
    missing_sales_title,
    "url"
].apply(title_from_url)


# ------------------------------------------------------------
# MATCH YEAR
# ------------------------------------------------------------

sales_work["year"] = (
    to_nullable_int(
        sales_work["year"]
    )
)

sales_release_year = (
    pd.to_datetime(
        sales_work["release_date"],
        format="mixed",
        errors="coerce"
    )
    .dt.year
    .astype("Int64")
)

sales_work["match_year"] = (
    sales_work["year"].copy()
)

# Nuria's useful idea:
# only use release_date year when year itself is missing.
sales_work.loc[
    sales_work["match_year"].isna(),
    "match_year"
] = sales_release_year[
    sales_work["match_year"].isna()
]


# ------------------------------------------------------------
# NORMALIZED MATCHING KEY
# ------------------------------------------------------------

sales_work["title_key"] = (
    sales_work["sales_title"]
    .apply(title_key)
)


# ------------------------------------------------------------
# NUMERIC SALES DATA
# ------------------------------------------------------------

money_columns = [
    "production_budget",
    "domestic_box_office",
    "international_box_office",
    "worldwide_box_office",
    "opening_weekend"
]

for col in money_columns:

    sales_work[col] = clean_money(
        sales_work[col]
    )


sales_work["theatre_count"] = (
    to_nullable_int(
        sales_work["theatre_count"]
    )
)


sales_work["keywords"] = (
    sales_work["keywords"]
    .apply(clean_text)
)

sales_work["creative_type"] = (
    sales_work["creative_type"]
    .apply(clean_text)
)
```

### Step 8 – SALES: match with movies

Sales and movies share no ID, so they are matched on the normalised title **and the exact release year**. Titles that appear twice with the same year (Dreamland, Swan Song, The Hunter) are never matched automatically.

```python
movie_match = movie[
    [
        "movie_id",
        "title",
        "release_date"
    ]
].copy()

movie_match = movie_match.rename(
    columns={
        "title": "movie_title"
    }
)

movie_match["title_key"] = (
    movie_match["movie_title"]
    .apply(title_key)
)

movie_match["match_year"] = (
    movie_match["release_date"]
    .dt.year
    .astype("Int64")
)


# Find duplicate movie title + year combinations
ambiguous_movie_matches = (
    movie_match[
        movie_match.duplicated(
            [
                "title_key",
                "match_year"
            ],
            keep=False
        )
    ]
    .sort_values(
        [
            "title_key",
            "match_year"
        ]
    )
)


print(
    "Ambiguous movie rows:",
    len(ambiguous_movie_matches)
)

display(
    ambiguous_movie_matches
)


# Do NOT auto-match these
movie_match_unique = (
    movie_match
    .drop_duplicates(
        [
            "title_key",
            "match_year"
        ],
        keep=False
    )
)
```

```python
matched = sales_work.merge(

    movie_match_unique[
        [
            "movie_id",
            "movie_title",
            "title_key",
            "match_year"
        ]
    ],

    on=[
        "title_key",
        "match_year"
    ],

    how="inner",

    validate="many_to_one"
)


print(
    "Matched source rows:",
    len(matched)
)

print(
    "Unique movies:",
    matched["movie_id"]
    .nunique()
)
```

### Step 9 – SALES: resolve conflicts

Nine movies have several different sales rows. Each is resolved only with explicit evidence (URL, budget, theatre count). Seven are resolved; two cannot be resolved and are excluded. A row is never picked at random. Result: 8,377 movies with sales.

```python
sales_columns = [

    "year",

    "production_budget",

    "domestic_box_office",

    "international_box_office",

    "worldwide_box_office",

    "opening_weekend",

    "theatre_count"
]


conflict_ids = []


for movie_id, group in matched.groupby(
    "movie_id"
):

    if len(group) <= 1:
        continue

    different_versions = (
        group[
            sales_columns
        ]
        .drop_duplicates()
    )

    if len(different_versions) > 1:

        conflict_ids.append(
            movie_id
        )


sales_conflicts = matched[
    matched["movie_id"]
    .isin(conflict_ids)
].copy()


print(
    "Conflicting movie IDs:",
    len(conflict_ids)
)

display(
    sales_conflicts[
        [
            "movie_id",
            "movie_title",
            "year",
            "url",
            "production_budget",
            "domestic_box_office",
            "international_box_office",
            "worldwide_box_office",
            "theatre_count",
            "creative_type"
        ]
    ].sort_values(
        ["movie_title", "movie_id"]
    )
)
```

```python
def contains_text(series, text):

    return (
        series
        .astype("string")
        .str.contains(
            text,
            case=False,
            regex=False,
            na=False
        )
    )


def choose_sales_row(group):

    title = group[
        "movie_title"
    ].iloc[0]

    year = group[
        "match_year"
    ].iloc[0]


    mask = pd.Series(
        False,
        index=group.index
    )


    # Luca 2021
    if (
        title == "Luca"
        and year == 2021
    ):

        mask = (
            contains_text(
                group["url"],
                "Luca-(2021)"
            )
            |
            group[
                "creative_type"
            ].eq(
                "Kids Fiction"
            )
        )


    # Run 2020
    elif (
        title == "Run"
        and year == 2020
    ):

        mask = (
            group[
                "production_budget"
            ].eq(
                4_500_000
            )
        )


    # The Interpreter 2005
    elif (
        title == "The Interpreter"
        and year == 2005
    ):

        max_domestic = (
            group[
                "domestic_box_office"
            ]
            .max()
        )

        mask = (
            group[
                "domestic_box_office"
            ].eq(
                max_domestic
            )
        )


    # The Outsider 2018
    elif (
        title == "The Outsider"
        and year == 2018
    ):

        mask = (
            group[
                "creative_type"
            ].eq(
                "Historical Fiction"
            )
        )


    # Thirst 2009
    elif (
        title == "Thirst"
        and year == 2009
    ):

        mask = (
            group[
                "domestic_box_office"
            ].between(
                300_000,
                400_000
            )
        )


    # Val 2021
    elif (
        title == "Val"
        and year == 2021
    ):

        mask = (
            group[
                "creative_type"
            ].eq(
                "Factual"
            )
        )


    # White Noise 2005
    elif (
        title == "White Noise"
        and year == 2005
    ):

        mask = (
            contains_text(
                group["url"],
                "White-Noise-(2005)"
            )
            |
            group[
                "theatre_count"
            ].eq(
                2261
            )
        )


    # Wuthering Heights 2012
    elif (
        title == "Wuthering Heights"
        and year == 2012
    ):

        mask = contains_text(
            group["url"],
            "Wuthering-Heights-(2011)"
        )


    # Aftermath 2014
    elif (
        title == "Aftermath"
        and year == 2014
    ):

        mask = contains_text(
            group["url"],
            "Aftermath-(2012)"
        )


    selected = (
        group[mask]
        .drop_duplicates(
            "_source_row"
        )
    )


    # VERY IMPORTANT:
    # never randomly pick one
    if len(selected) == 1:

        return selected.iloc[0]


    return None
```

```python
# Non-conflicting records
non_conflict = (

    matched[
        ~matched["movie_id"]
        .isin(conflict_ids)
    ]

    .sort_values(
        "_source_row"
    )

    .drop_duplicates(
        "movie_id",
        keep="first"
    )
)


resolved = []

unresolved = []


for movie_id in conflict_ids:

    group = matched[
        matched[
            "movie_id"
        ].eq(movie_id)
    ].copy()


    selected = choose_sales_row(
        group
    )


    if selected is None:

        unresolved.append(
            group
        )

    else:

        resolved.append(
            selected
        )


resolved_conflicts = (
    pd.DataFrame(resolved)
    if resolved
    else matched.iloc[0:0].copy()
)


unresolved_conflicts = (
    pd.concat(
        unresolved,
        ignore_index=True
    )
    if unresolved
    else matched.iloc[0:0].copy()
)


selected_sales = pd.concat(
    [
        non_conflict,
        resolved_conflicts
    ],
    ignore_index=True
)


selected_sales = (
    selected_sales
    .drop_duplicates(
        "movie_id",
        keep=False
    )
)


sales = selected_sales[
    [
        "movie_id",
        "year",
        "production_budget",
        "domestic_box_office",
        "international_box_office",
        "worldwide_box_office",
        "opening_weekend",
        "theatre_count"
    ]
].copy()


print(
    "Final SALES:",
    len(sales)
)

print(
    "Resolved conflicts:",
    len(resolved_conflicts)
)

print(
    "Unresolved conflicts:",
    unresolved_conflicts[
        "movie_id"
    ].nunique()
)
```

```python
movie_attributes = (
    selected_sales[
        [
            "movie_id",
            "keywords",
            "creative_type"
        ]
    ]
    .drop_duplicates(
        "movie_id"
    )
)


movie = (
    movie
    .drop(
        columns=[
            "keywords",
            "creative_type"
        ]
    )
    .merge(
        movie_attributes,
        on="movie_id",
        how="left",
        validate="one_to_one"
    )
)
```

### Step 10 – EXPERT_REVIEW

Reviews without text and exact duplicates are removed (2 and 27 rows). Scores outside 0 to 100 and LIWC values outside 0 to 100 become NULL. If the word count is 0 or missing, the LIWC values are set to NULL but the review is kept. Each review is linked to its movie through the Metacritic URL. Result: 238,944 reviews.

```python
expert = expert_raw.copy()


expert["url"] = (
    expert["url"]
    .apply(clean_text)
)

expert["reviewer"] = (
    expert["reviewer"]
    .apply(clean_review_text)
)

expert["Rev"] = (
    expert["Rev"]
    .apply(clean_review_text)
)


expert["date_posted"] = (
    parse_review_dates(
        expert["dateP"]
    )
)


expert["review_score"] = (
    pd.to_numeric(
        expert["idvscore"],
        errors="coerce"
    )
)


expert["word_count"] = (
    to_nullable_int(
        expert["WC"]
    )
)


emotion_mapping = {

    "Tone": "tone",

    "posemo": "posemo",

    "negemo": "negemo",

    "anx": "anx",

    "anger": "anger",

    "sad": "sad"
}


for original, clean_name in emotion_mapping.items():

    expert[clean_name] = (
        pd.to_numeric(
            expert[original],
            errors="coerce"
        )
    )


# ------------------------------------------------------------
# REMOVE REVIEWS WITHOUT TEXT
# ------------------------------------------------------------

before = len(expert)

expert = expert[
    expert["Rev"].notna()
].copy()

print(
    "Missing text removed:",
    before - len(expert)
)


# ------------------------------------------------------------
# INVALID SCORES -> NULL
# ------------------------------------------------------------

invalid_score = (

    expert["review_score"]
    .notna()

    &

    ~expert[
        "review_score"
    ].between(
        0,
        100
    )
)

expert.loc[
    invalid_score,
    "review_score"
] = np.nan


# ------------------------------------------------------------
# LIWC VALIDATION
# ------------------------------------------------------------

emotion_cols = [
    "tone",
    "posemo",
    "negemo",
    "anx",
    "anger",
    "sad"
]


for col in emotion_cols:

    invalid = (

        expert[col].notna()

        &

        ~expert[col].between(
            0,
            100
        )
    )

    expert.loc[
        invalid,
        col
    ] = np.nan


bad_liwc = (

    expert["word_count"].isna()

    |

    (expert["word_count"] <= 0)
)


expert.loc[
    bad_liwc,
    ["word_count"] + emotion_cols
] = pd.NA


# ------------------------------------------------------------
# DEDUPLICATE
# ------------------------------------------------------------

duplicate_columns = [

    "url",

    "reviewer",

    "date_posted",

    "Rev",

    "review_score"
]


before = len(expert)


expert = expert.drop_duplicates(
    duplicate_columns,
    keep="first"
)


print(
    "Duplicates removed:",
    before - len(expert)
)


# ------------------------------------------------------------
# MATCH TO MOVIE
# ------------------------------------------------------------

expert = expert.merge(

    movie[
        [
            "movie_id",
            "metacritic_url"
        ]
    ],

    left_on="url",

    right_on="metacritic_url",

    how="left",

    validate="many_to_one"
)


print(
    "Unmatched:",
    expert["movie_id"]
    .isna()
    .sum()
)


expert = expert[
    expert["movie_id"]
    .notna()
].copy()


expert["movie_id"] = (
    expert["movie_id"]
    .astype("Int64")
)


expert = expert.reset_index(
    drop=True
)


expert.insert(
    0,
    "review_id",
    range(
        1,
        len(expert) + 1
    )
)


expert_review = expert[
    [
        "review_id",
        "movie_id",
        "reviewer",
        "date_posted",
        "Rev",
        "review_score",
        "word_count",
        "tone",
        "posemo",
        "negemo",
        "anx",
        "anger",
        "sad"
    ]
].copy()


expert_review = (
    expert_review.rename(
        columns={
            "Rev":
                "review_text"
        }
    )
)


print(
    "FINAL EXPERT:",
    len(expert_review)
)
```

### Step 11 – CONSUMER_REVIEW

Same rules as for experts, with consumer scores valid from 0 to 10, and invalid thumbs-up counts set to NULL. 3,413 reviews without text and 124 duplicates are removed. Result: 316,125 reviews.

```python
consumer = consumer_raw.copy()


consumer["url"] = (
    consumer["url"]
    .apply(clean_text)
)

consumer["reviewer"] = (
    consumer["reviewer"]
    .apply(clean_review_text)
)

consumer["Rev"] = (
    consumer["Rev"]
    .apply(clean_review_text)
)


consumer["date_posted"] = (
    parse_review_dates(
        consumer["dateP"]
    )
)


consumer["review_score"] = (
    pd.to_numeric(
        consumer["idvscore"],
        errors="coerce"
    )
)


consumer["word_count"] = (
    to_nullable_int(
        consumer["WC"]
    )
)


consumer["thumbs_up"] = (
    to_nullable_int(
        consumer["thumbsUp"]
    )
)

consumer["thumbs_total"] = (
    to_nullable_int(
        consumer["thumbsTot"]
    )
)


consumer["tone"] = (
    pd.to_numeric(
        consumer["Tone"],
        errors="coerce"
    )
)


for col in [
    "posemo",
    "negemo",
    "anx",
    "anger",
    "sad"
]:

    consumer[col] = (
        pd.to_numeric(
            consumer[col],
            errors="coerce"
        )
    )


# ------------------------------------------------------------
# INVALID THUMBS -> NULL
# ------------------------------------------------------------

invalid_votes = (

    (
        consumer["thumbs_up"]
        .notna()
        &
        (
            consumer[
                "thumbs_up"
            ] < 0
        )
    )

    |

    (
        consumer[
            "thumbs_total"
        ].notna()
        &
        (
            consumer[
                "thumbs_total"
            ] < 0
        )
    )

    |

    (
        consumer[
            "thumbs_up"
        ].notna()

        &

        consumer[
            "thumbs_total"
        ].notna()

        &

        (
            consumer[
                "thumbs_up"
            ]
            >
            consumer[
                "thumbs_total"
            ]
        )
    )
)


consumer.loc[
    invalid_votes,
    [
        "thumbs_up",
        "thumbs_total"
    ]
] = pd.NA


# ------------------------------------------------------------
# REMOVE REVIEWS WITHOUT TEXT
# ------------------------------------------------------------

before = len(consumer)


consumer = consumer[
    consumer["Rev"]
    .notna()
].copy()


print(
    "Missing text removed:",
    before - len(consumer)
)


# ------------------------------------------------------------
# SCORE VALIDATION
# ------------------------------------------------------------

invalid_score = (

    consumer[
        "review_score"
    ].notna()

    &

    ~consumer[
        "review_score"
    ].between(
        0,
        10
    )
)


consumer.loc[
    invalid_score,
    "review_score"
] = np.nan


# ------------------------------------------------------------
# LIWC VALIDATION
# ------------------------------------------------------------

for col in emotion_cols:

    invalid = (

        consumer[col]
        .notna()

        &

        ~consumer[col]
        .between(
            0,
            100
        )
    )

    consumer.loc[
        invalid,
        col
    ] = np.nan


bad_consumer_liwc = (

    consumer[
        "word_count"
    ].isna()

    |

    (
        consumer[
            "word_count"
        ] <= 0
    )
)


consumer.loc[
    bad_consumer_liwc,
    ["word_count"] + emotion_cols
] = pd.NA


# ------------------------------------------------------------
# DUPLICATES
# ------------------------------------------------------------

consumer_duplicate_columns = [

    "url",

    "reviewer",

    "date_posted",

    "Rev",

    "review_score",

    "thumbs_up",

    "thumbs_total"
]


before = len(consumer)


consumer = (
    consumer
    .drop_duplicates(
        consumer_duplicate_columns,
        keep="first"
    )
)


print(
    "Duplicates removed:",
    before - len(consumer)
)


# ------------------------------------------------------------
# MATCH MOVIE
# ------------------------------------------------------------

consumer = consumer.merge(

    movie[
        [
            "movie_id",
            "metacritic_url"
        ]
    ],

    left_on="url",

    right_on="metacritic_url",

    how="left",

    validate="many_to_one"
)


print(
    "Unmatched:",
    consumer[
        "movie_id"
    ].isna().sum()
)


consumer = consumer[
    consumer[
        "movie_id"
    ].notna()
].copy()


consumer[
    "movie_id"
] = consumer[
    "movie_id"
].astype("Int64")


consumer = consumer.reset_index(
    drop=True
)


consumer.insert(

    0,

    "review_id",

    range(
        1,
        len(consumer) + 1
    )
)


consumer_review = consumer[
    [
        "review_id",
        "movie_id",
        "reviewer",
        "date_posted",
        "Rev",
        "review_score",
        "thumbs_up",
        "thumbs_total",
        "word_count",
        "tone",
        "posemo",
        "negemo",
        "anx",
        "anger",
        "sad"
    ]
].copy()


consumer_review = (
    consumer_review.rename(
        columns={
            "Rev":
                "review_text"
        }
    )
)


print(
    "FINAL CONSUMER:",
    len(consumer_review)
)
```

### Step 12 – Row counts and validation

The final row counts of the ten tables, and checks for duplicate IDs, duplicate junction rows and broken foreign keys. Every check must return 0.

```python
print(
    "========== ROW COUNTS =========="
)

print(
    "MOVIE",
    len(movie)
)

print(
    "SALES",
    len(sales)
)

print(
    "GENRE",
    len(genre)
)

print(
    "MOVIE_GENRE",
    len(movie_genre)
)

print(
    "ACTOR",
    len(actor)
)

print(
    "MOVIE_CAST",
    len(movie_cast)
)

print(
    "AWARD",
    len(award)
)

print(
    "MOVIE_AWARD",
    len(movie_award)
)

print(
    "EXPERT_REVIEW",
    len(expert_review)
)

print(
    "CONSUMER_REVIEW",
    len(consumer_review)
)
```

```python
checks = {

    "MOVIE duplicate ID":
        movie["movie_id"]
        .duplicated()
        .sum(),

    "SALES duplicate ID":
        sales["movie_id"]
        .duplicated()
        .sum(),

    "GENRE duplicate ID":
        genre["genre_id"]
        .duplicated()
        .sum(),

    "ACTOR duplicate ID":
        actor["actor_id"]
        .duplicated()
        .sum(),

    "AWARD duplicate ID":
        award["award_id"]
        .duplicated()
        .sum(),

    "EXPERT duplicate ID":
        expert_review[
            "review_id"
        ]
        .duplicated()
        .sum(),

    "CONSUMER duplicate ID":
        consumer_review[
            "review_id"
        ]
        .duplicated()
        .sum(),

    "MOVIE_GENRE duplicates":
        movie_genre
        .duplicated(
            [
                "movie_id",
                "genre_id"
            ]
        )
        .sum(),

    "MOVIE_CAST duplicates":
        movie_cast
        .duplicated(
            [
                "movie_id",
                "actor_id"
            ]
        )
        .sum(),

    "MOVIE_AWARD duplicates":
        movie_award
        .duplicated(
            [
                "movie_id",
                "award_id"
            ]
        )
        .sum(),

    "SALES -> MOVIE":
        (
            ~sales[
                "movie_id"
            ].isin(
                movie[
                    "movie_id"
                ]
            )
        ).sum(),

    "GENRE -> MOVIE":
        (
            ~movie_genre[
                "movie_id"
            ].isin(
                movie[
                    "movie_id"
                ]
            )
        ).sum(),

    "CAST -> MOVIE":
        (
            ~movie_cast[
                "movie_id"
            ].isin(
                movie[
                    "movie_id"
                ]
            )
        ).sum(),

    "AWARD -> MOVIE":
        (
            ~movie_award[
                "movie_id"
            ].isin(
                movie[
                    "movie_id"
                ]
            )
        ).sum(),

    "EXPERT -> MOVIE":
        (
            ~expert_review[
                "movie_id"
            ].isin(
                movie[
                    "movie_id"
                ]
            )
        ).sum(),

    "CONSUMER -> MOVIE":
        (
            ~consumer_review[
                "movie_id"
            ].isin(
                movie[
                    "movie_id"
                ]
            )
        ).sum()
}


for name, value in checks.items():

    print(
        f"{name:30} {value}"
    )
```

### Step 13 – Export the ten CSV files

Each table is saved as a UTF-8 CSV file, ready to import into PostgreSQL.

```python
movie.to_csv(
    "movie.csv",
    index=False,
    encoding="utf-8",
    date_format="%Y-%m-%d"
)

sales.to_csv(
    "sales.csv",
    index=False,
    encoding="utf-8"
)

genre.to_csv(
    "genre.csv",
    index=False,
    encoding="utf-8"
)

movie_genre.to_csv(
    "movie_genre.csv",
    index=False,
    encoding="utf-8"
)

actor.to_csv(
    "actor.csv",
    index=False,
    encoding="utf-8"
)

movie_cast.to_csv(
    "movie_cast.csv",
    index=False,
    encoding="utf-8"
)

award.to_csv(
    "award.csv",
    index=False,
    encoding="utf-8"
)

movie_award.to_csv(
    "movie_award.csv",
    index=False,
    encoding="utf-8"
)

expert_review.to_csv(
    "expert_review.csv",
    index=False,
    encoding="utf-8",
    date_format="%Y-%m-%d"
)

consumer_review.to_csv(
    "consumer_review.csv",
    index=False,
    encoding="utf-8",
    date_format="%Y-%m-%d"
)


print("All 10 CSV files saved.")
```

