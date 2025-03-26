```sql
select 
DISTINCT Id,
owner AS team,
region
From `tab`
where Id IS NOT NUll
and REGEXP_CONTAINS(Id,r'^\d+$')
```