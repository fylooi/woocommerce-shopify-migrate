# woocommerce-shopify-migrate
Ruby scripts to migrate WooCommerce products to Shopify

These scripts form an ETL process to migrate scripts to Shopify. They have been used in the following environment:

- Wordpress 4.4.3
- WooCommerce 2.5.3
- https://wordpress.org/plugins/amazon-s3-and-cloudfront/

Product data is exported with https://wordpress.org/plugins/woocommerce-exporter/

The ETL process is as follows: 

1. Export WooCommerce data to CSV in Wordpress with stock settings. If the Ruby CSV library is unable to parse this file, use something like Microsoft Excel to re-save into a standard CSV format. Rename this file to `woocommerce_export.csv`.

2. Export image attachment Cloudfront URLs using a direct DB query (included in 'attachments.rb') as `wp_postmeta.csv`. 

3. Put everything in the same working directory and run `irb` there. 

4. Execute the following commands:

```
load 'attachments.rb'
run
load 'transform.rb'
run
```

5. This will generate `table.csv`, which is ready for upload to Shopify 

