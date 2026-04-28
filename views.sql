-- Country Sales Performance View
create view vw_country_sales_performance as  
with country_aggregations as (
select
	c.country,
	sum(s.sales_amount) as total_sales_per_country,
	sum(s.quantity) as total_quantity,
	count(distinct s.order_number) as number_of_orders,
	count(distinct c.customer_key) as number_of_customers
from dbo.fact_sales s
left join gold.dim_customers c
on s.customer_key = c.customer_key
where c.country <> 'n/a' and c.country is not null
group by c.country
), sales_all_countries as (
	select
		country,
		total_quantity,
		total_sales_per_country,
		number_of_orders,
		number_of_customers,
		sum(total_sales_per_country) over ()as total_sales_all_countries
	from country_aggregations
)
 select 
	country,
	total_quantity,
	total_sales_per_country,
	number_of_orders,
	number_of_customers,
	case
		when total_sales_all_countries <> 0 then round(total_sales_per_country / cast(total_sales_all_countries as float) * 100, 2) 
		else null
	end as percentage_sales_of_all_countries,
	DENSE_RANK() over (order by total_sales_per_country desc) as ranking_by_sales
 from sales_all_countries;




-- Monthly Sales Growth View
create view vw_monthly_sales_growth as
with monthly_sales as (
	select
		year(s.order_date) as year,
		month(s.order_date) as month,
		DATETRUNC(month, s.order_date) as month_trunc,
		sum(s.sales_amount) as total_sales_that_month,
		sum(s.quantity) as total_quantity,
		count(distinct s.order_number) as total_orders
	from dbo.fact_sales s
	where s.order_date is not null
	group by 
		year(s.order_date),
		month(s.order_date),
		DATETRUNC(month, s.order_date)
), monthly_sales_with_previous as (
	select
		year,
		month,
		month_trunc,
		total_orders,
		total_quantity,
		total_sales_that_month,
		lag(total_sales_that_month) over (order by month_trunc) as previous_month
	from monthly_sales
), monthly_sales_growth as (
select 
	year,
	month,
	month_trunc,
	total_orders,
	total_quantity,
	total_sales_that_month,
	previous_month,
	total_sales_that_month - previous_month as growth,
	case
		when previous_month = 0 or previous_month is null then null
		else 
			round((total_sales_that_month - cast(previous_month as float)) / cast(previous_month as float) * 100 , 2) 
	end as growth_percentage
from monthly_sales_with_previous
)
select * 
from monthly_sales_growth;




-- Product Category Performance View
create view vw_product_category_performance as
with sales_per_product_and_category as (
select
	p.product_name,
	p.category,
	sum(s.sales_amount) as total_sales_that_product,
	sum(s.quantity) as total_quantity
from dbo.fact_sales s
left join gold.dim_products p 
on s.product_key = p.product_key
group by
	p.product_name,
	p.category
), sales_by_categories as (
	select
		product_name,
		category,
		total_sales_that_product,
		total_quantity,
		sum(total_sales_that_product) over (partition by category) sales_by_category
	from sales_per_product_and_category
), ranking_and_percentage_of_sales_in_category as (
	select
		product_name,
		category,
		total_quantity,
		total_sales_that_product,
		sales_by_category,
		case
			when sales_by_category <> 0 then round(total_sales_that_product / cast(sales_by_category as float) * 100, 2)
			else null
		end as percentage_of_sales_for_that_category,
		DENSE_RANK() over (partition by category order by total_sales_that_product desc) as ranking_by_sales_in_category
	from sales_by_categories
)
select *
from ranking_and_percentage_of_sales_in_category;




-- Customer Sales Performance View
create view vw_customer_sales_performance as
 with customer_aggregations as (
 select
	c.customer_id,
	trim(concat(coalesce(c.first_name, ''), ' ', coalesce(c.last_name, ''))) as customer_name,
	c.country,
	sum(s.sales_amount) as total_sales,
	sum(s.quantity) as total_quantity,
	count(distinct s.order_number) number_of_orders,
	min(s.order_date) as first_order_date,
	max(s.order_date) as last_order_date
from dbo.fact_sales s
left join gold.dim_customers c
on s.customer_key = c.customer_key
where s.order_date is not null
group by 
	c.customer_id,
	trim(concat(coalesce(c.first_name, ''), ' ', coalesce(c.last_name, ''))),
	c.country
 ), customer_avg_sales as (
	select
		customer_id,
		customer_name,
		country,
		total_sales,
		case
			when number_of_orders <> 0 then round(total_sales / cast(number_of_orders as float), 2)
			else null
		end as avg_order_value,
		total_quantity,
		number_of_orders,
		first_order_date,
		last_order_date
	from customer_aggregations
 ), ranking as (
	select
		customer_id,
		customer_name,
		country,
		total_sales,
		avg_order_value,
		total_quantity,
		number_of_orders,
		first_order_date,
		last_order_date,
		DENSE_RANK() over (order by total_sales desc) as ranking_by_sales
	from customer_avg_sales
 )
	 select 
		customer_id,
		customer_name,
		country,
		total_sales,
		avg_order_value,
		total_quantity,
		number_of_orders,
		first_order_date,
		last_order_date,
		ranking_by_sales,
	 case 
		when total_sales > 5000 then 'High'
		when total_sales between 2000 and 5000 then 'Medium'
		else 'Low'
	end as segmentation_by_sales
	 from ranking;




-- Product sales Performance View
create view vw_product_sales_performance as
with sales_per_product_and_category as (
select
	p.product_name,
	p.category,
	sum(s.sales_amount) as total_sales_that_product,
	sum(s.quantity) as total_quantity
from dbo.fact_sales s
left join gold.dim_products p 
on s.product_key = p.product_key
group by
	p.product_name,
	p.category
), sales_per_all_product as (
	select 
		product_name,
		category,
		total_sales_that_product,
		sum(total_sales_that_product) over() as total_sales_of_all,
		total_quantity
	from sales_per_product_and_category
), percentage_of_sales as (
	select
		product_name,
		category,
		total_quantity,
		total_sales_that_product,
		total_sales_of_all,
		round(cast(total_sales_that_product as float) / total_sales_of_all * 100, 2) as percentage_of_total_sales
	from sales_per_all_product
), sales_ranking as (
	select
		product_name,
		category,
		total_quantity,
		total_sales_that_product,
		total_sales_of_all,
		percentage_of_total_sales,
		DENSE_RANK() over (order by total_sales_that_product desc) ranking_by_sales
	from percentage_of_sales
) 
select
	*
from sales_ranking;
