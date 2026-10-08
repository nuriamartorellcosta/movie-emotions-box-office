Emotions in Movie Reviews and Box Office Revenue

Database Management Project, Group 14. Master Digital Driven Business, Amsterdam University of Applied Sciences (HvA).

Authors: Alexandra Maria Drasovean, Nuria Martorell Costa, Zein Abou El Kheir

What this project does

The project builds a PostgreSQL database that links the emotional language of movie reviews to box-office revenue. It then tests four hypotheses with Pearson and Spearman correlations.

Main research question: To what extent do emotional expressions in consumer and expert movie reviews relate to box-office performance?

Emotion is measured with LIWC2015 (positive emotion, negative emotion, anxiety, anger, sadness and tone). Reviews come from Metacritic and box office from the-numbers.com, covering 11,364 movies.

How the project works
Extract: four source files are read into Python.
Transform: Python and pandas clean the data and build ten tables that match the final ERD.
Load: the ten tables are loaded into PostgreSQL.
Analyse: SQL queries and a Python encapsulator run the correlation tests.

The transformation happens before loading, so this is an ETL process, not ELT.

Repository contents
File	Purpose
ALL_cleaned_FINAL.ipynb	Data cleaning pipeline (pandas), exports the ten CSV files
TEAM_MASTER_CLEANING_AND_POSTGRES.ipynb	Same cleaning plus automatic creation and loading of the PostgreSQL tables
Movie_encapsulator.ipynb	Python encapsulator and correlation analysis
python/README.md	Separate README explaining the encapsulator
sql/database_and_analysis.sql	Table definitions, the analysis view and the correlation queries (SQ1 to SQ4)
h1_results.csv ... h4_results.csv, main_rq_results.csv	Correlation results exported by the encapsulator

The raw source files are not included because of their size: metaClean43Brightspace.xlsx, sales.xlsx, UserReviewsClean43LIWC.xlsx and ExpertReviewsClean43LIWC.xlsx.

Data cleaning

The cleaning is done in pandas. Every decision is explicit, and nothing is deleted when it can be set to NULL instead.

Source data
Source file	Raw rows	Content
metaClean43Brightspace.xlsx	11,364	Movie description from Metacritic (title, studio, rating, runtime, metascore, genres, cast, awards)
sales.xlsx	30,612	Budget and box office from the-numbers.com
ExpertReviewsClean43LIWC.xlsx	238,973	Critic reviews with LIWC scores
UserReviewsClean43LIWC.xlsx	319,662	Audience reviews with LIWC scores
Cleaning steps
Stable movie ID. Each movie gets a movie_id from the original Metacritic row order.
Text repair. The library ftfy fixes broken encoding (for example CittÃ becomes Città). Control characters and extra spaces are removed, and words such as none, null or nan become real NULL values.
Standardising values. Ratings are unified (PG--13 becomes PG-13, NR becomes Not Rated). Confirmed typos in titles, directors and actor names are fixed by hand. One wrong runtime (The Tenants, 31 minutes) is set to NULL instead of inventing a value.
Splitting lists into tables. Genres, actors and awards are stored as comma-separated text in the source. They are split into one row per value, de-duplicated, and linked to movies through the junction tables movie_genre, movie_cast and movie_award (normalisation).
Matching sales to movies. Sales and movies share no ID, so they are matched on a normalised title (no accents, punctuation or capitals; "Name, The" becomes "The Name") and the exact release year. Titles that appear twice with the same year (Dreamland, Swan Song, The Hunter) are never matched automatically.
Conflicting sales rows. Nine movies had several different sales rows. Seven were resolved with explicit evidence (URL, budget or theatre count) and two could not be resolved, so they are excluded. A row is never picked at random.
Money and numbers. Dollar signs and commas are removed. Values that are not whole numbers are not rounded silently.
Reviews. Reviews without text are removed, exact duplicates are removed, scores outside their valid range (0 to 100 for experts, 0 to 10 for consumers) become NULL, LIWC values outside 0 to 100 become NULL, and if the word count is 0 or missing the LIWC values are set to NULL but the review is kept.
Linking reviews. Each review is linked to its movie through the Metacritic URL. No review was left unmatched.
Validation. Before export, the notebook checks for duplicate IDs, duplicate junction rows and broken foreign keys. All checks return 0.

Example of the matching key used in step 5:

python
def title_key(value):
    value = reorder_article(value)                    # "Name, The" -> "The Name"
    value = unicodedata.normalize("NFKD", str(value))
    value = "".join(c for c in value if not unicodedata.combining(c))  # remove accents
    value = re.sub(r"[^a-z0-9]", "", value.casefold())                 # keep letters and digits only
    return value if value else pd.NA
Result of the cleaning
Table	Rows
movie	11,364
sales	8,377 (of 30,612 raw rows; only exact title and year matches are kept)
consumer_review	316,125 (3,413 without text and 124 duplicates removed)
expert_review	238,944 (2 without text and 27 duplicates removed)
genre / movie_genre	27 / 27,051
actor / movie_cast	24,855 / 48,280
award / movie_award	6,407 / 6,409
Database

Database name: movies_project (PostgreSQL).

Table	Content
movie	Movie description (central table)
sales	Budget and box office, one row per movie
consumer_review	Audience reviews with LIWC emotion scores
expert_review	Critic reviews with LIWC emotion scores
genre, movie_genre	Genres and their link to movies
actor, movie_cast	Actors and their link to movies
award, movie_award	Awards and their link to movies

The view movie_emotion_analysis (created in sql/database_and_analysis.sql) gives one row per movie with its average consumer and expert emotions and its box-office figures.

How to run it
Install PostgreSQL and pgAdmin, then create an empty database called movies_project.
Install the Python libraries:
   pip install pandas numpy openpyxl scipy statsmodels psycopg2-binary ftfy
Put the four source files in the same folder as the notebooks.
Clean and load the data. Open TEAM_MASTER_CLEANING_AND_POSTGRES.ipynb, set the folder path (DATA_DIR) and DB_NAME = "movies_project", and run all cells. It cleans the data, creates the ten tables and loads them into PostgreSQL. It asks for your password and never stores it. (Alternative: run ALL_cleaned_FINAL.ipynb to get the ten CSV files, create the tables with the SQL script and import the CSV files in this order: movie, then genre, actor, award, then sales, movie_genre, movie_cast, movie_award, and finally expert_review and consumer_review.)
Run the SQL script sql/database_and_analysis.sql in pgAdmin (Query Tool) to create the view and run the SQL correlation queries.
Open Movie_encapsulator.ipynb and run all cells in order (see the encapsulator README).
Python encapsulator

The Python encapsulator (Movie_encapsulator.ipynb) queries the database and returns pandas DataFrames, then runs the Pearson and Spearman tests for H1 to H4. Its functions, code and verification are explained in its own README: python/README.md.
