
--https://www.postgresql.org/docs/current/textsearch-features.html

SELECT 
    word,nentry                                       
FROM  
    ts_stat('SELECT to_tsvector(contents) FROM google_file_store') 
WHERE
    word ILIKE 'bull' or word ILIKE 'bear'

SELECT 
    word,
    nentry                                       
FROM  
    ts_stat('SELECT to_tsvector(contents) FROM google_file_store where filename ILIKE ''draft%''')