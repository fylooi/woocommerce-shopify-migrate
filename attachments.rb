require 'csv'
require 'pry'

# extract AWS S3 urls from post meta with following query
#
# select post_id, meta_value
# from wp_postmeta
# inner join wp_posts on wp_postmeta.post_id = wp_posts.id
# where wp_posts.post_type = 'attachment' and wp_postmeta.meta_key = 'amazonS3_info'
#

ATTACHMENT_FILENAME = 'wp_postmeta.csv'
EXPORT_FILENAME = 'woocommerce_export.csv'
CLOUDFRONT_HOST_URL = "http://host.cloudfront.net/"

def run(original_source_file = EXPORT_FILENAME)
  reload
  output_file = source_with_attachments_merged(original_source_file)
  write_table(output_file, 'woocommerce_export_merged.csv')
end

def source_with_attachments_merged(original_source_file)
  attachment_table = open_csv_table(ATTACHMENT_FILENAME)
  source_file_table = open_csv_table(original_source_file)

  source_file_table.each do |row|
    if row['Product Gallery']
      row['Product Gallery'] = replace_with_attachments(attachment_table, row['Product Gallery'])
    end
  end

  source_file_table
end

def replace_with_attachments attachment_table, row_values
  row_values.split('|').map do |attachment_id|
    result_row = attachment_table.find { |row| row['post_id'] == attachment_id.to_i }
    result_row && extract_url(result_row['meta_value']) or next
  end.join('|')
end

def extract_url(meta_value)
  CLOUDFRONT_HOST_URL + meta_value.split('"')[7]
end



def open_csv_table filename
  CSV.read( filename, { headers:           true,
                    converters:        :numeric,
                    header_converters: nil } )
end

def write_table table, filename
  File.open(filename, 'w') do |f|
    f.write table
  end
end

def reload
  load 'attachments.rb'
end
