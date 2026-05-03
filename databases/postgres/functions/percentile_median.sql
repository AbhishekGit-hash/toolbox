
select state, percentile_cont(0.5) within group (order by fraud_score desc) as percentile
from fraud_score_table
group by state