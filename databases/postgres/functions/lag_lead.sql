

-- General Syntax of LAG() and LEAD()

-- LAG(column_name, offset, default_value_if_null) OVER(PARTITION BY cols..., ORDER BY cols...) as col_alias

SELECT product_id, month,
  LAG(count,1,0) OVER(PARTITION BY product_id ORDER BY month) AS previous_count,
  count AS current_count,
  count - LAG(count,1,0) OVER(PARTITION BY product_id ORDER BY month) AS difference
FROM sale_product;



