Emotions in Movie Reviews and Box Office Revenue

Database Management Project, Group 14. Master Digital Driven Business, Amsterdam University of Applied Sciences (HvA).

Authors: Alexandra Maria Drasovean, Nuria Martorell Costa, Zein El Kheir

What this project does

The project builds a PostgreSQL database that links the emotional language of movie reviews to box-office revenue. It then tests four hypotheses with Pearson and Spearman correlations.

Main research question: To what extent do emotional expressions in consumer and expert movie reviews relate to box-office performance?

Emotion is measured with LIWC2015 (positive emotion, negative emotion, anxiety, anger, sadness and tone). Reviews and box office come from Metacritic and the-numbers.com, covering 11,364 movies.

How the project works
Extract: four source files are read into Python.
Transform: Python and pandas clean the data and build ten tables that match the final ERD.
Load: the ten tables are imported into PostgreSQL.
Analyse: a Python encapsulator queries the database and returns pandas DataFrames, then runs the correlation tests.

The transformation happens before loading, so this is an ETL process, not ELT.

Database

Database name: movies_project (PostgreSQL 18).

Table	Content
movie	Movie description (central table)
sales	Budget and box office, one row per movie
consumer_review	Audience reviews with LIWC emotion scores
expert_review	Critic reviews with LIWC emotion scores
genre, movie_genre	Genres and their link to movies
actor, movie_cast	Actors and their link to movies
award, movie_award	Awards and their link to movies

The view movie_emotion_analysis gives one row per movie with its average consumer and expert emotions and its box-office figures. All correlation queries use this view.

Files
File	Purpose
ALL_cleaned_FINAL.ipynb	Official data cleaning pipeline (pandas)
TEAM_MASTER_CLEANING_AND_POSTGRES.ipynb	Team cleaning and PostgreSQL loading notebook
Movie_encapsulator.ipynb	Python encapsulator and correlation analysis
sql/	Table definitions, the analysis view and the correlation queries
sq1_results.csv, sq2_results.csv, sq3_results.csv, sq4_results.csv, main_rq_results.csv	Correlation results exported by the encapsulator

The raw source files are not included because of their size. They are metaClean43Brightspace.xlsx, sales.xlsx, UserReviewsClean43LIWC.xlsx and ExpertReviewsClean43LIWC.xlsx.

How to run it
Install PostgreSQL and pgAdmin, then create an empty database called movies_project.
Install the Python libraries:
   pip install pandas numpy scipy statsmodels psycopg2-binary ftfy
Clean the data: run the cleaning notebook. It produces the ten CSV files, one per table.
Create the tables with the SQL in sql/.
Import the CSV files in this order, because of the foreign keys: movie, then genre, actor, award, then sales, movie_genre, movie_cast, movie_award, and finally expert_review and consumer_review.
Create the view movie_emotion_analysis.
Open Movie_encapsulator.ipynb. In the settings cell, set dbname to movies_project. Run all cells in order. The notebook asks for your PostgreSQL password and never stores it.
Encapsulator functions
Function	What it does
get_connection()	Opens the PostgreSQL connection
run_query(sql)	Runs any SQL and returns a DataFrame
get_movie_data()	One row per movie with box office, budget, genre and average review emotions
complete_rows()	Keeps movies with complete data, optionally without outliers
correlate()	Pearson (on log box office) and Spearman with p-values
correlation_table()	Runs a list of tests and returns one table
