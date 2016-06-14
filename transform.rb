require 'csv'
require 'pry'


# input file must not be in double quoted format
INPUT_FILENAME = 'woocommerce_export_merged.csv'
def input_filename; INPUT_FILENAME ; end

RENAME_HEADERS = {
  'Product SKU' => 'Variant SKU',
  'Product ID' => '_',
  'Parent ID' => '_1',
  'Parent SKU' => '_2',
  'Product Name' => 'Title',
  'Slug' => 'Handle',
  'Type' => '_3',
  'Description' => 'Body (HTML)',
  'Price' => 'Variant Price',
  'Sale Price' => 'Variant Compare At Price',
  'Category' => 'Type',
  'Tag' => '__', # do not convert tags
  'Featured Image' => 'Variant Image',
  'Product Gallery' => '_5',
  'Quantity' => 'Variant Inventory Qty',
  'Product Color' => 'Option1 Value',
  'Product Size' => 'Option2 Value',
  'Product Status' => '_6'
}

HEADERS = {
  'Handle' => nil,
  'Title' => nil,
  'Body (HTML)' => nil,
  'Vendor' => 'YOUR_VENDOR_NAME',
  'Type' => nil,
  'Tags' => nil,
  'Published' => 'TRUE',
  'Option1 Name' => 'Color',
  'Option1 Value' => nil,
  'Option2 Name' => 'Size',
  'Option2 Value' => nil,
  'Option3 Name' => nil,
  'Option3 Value' => nil,
  'Variant SKU' => nil,
  'Variant Grams' => '0',
  'Variant Inventory Tracker' => 'shopify',
  'Variant Inventory Qty' => nil,
  'Variant Inventory Policy' => 'deny',
  'Variant Fulfillment Service' => 'manual',
  'Variant Price' => nil,
  'Variant Compare At Price' => nil,
  'Variant Requires Shipping' => 'TRUE',
  'Variant Taxable' => nil,
  'Variant Barcode' => nil,
  'Image Src' => nil,
  'Image Alt Text' => nil,
  'Gift Card' => 'FALSE',
  'Google Shopping / MPN' => nil,
  'Google Shopping / Age Group' => nil,
  'Google Shopping / Gender' => nil,
  'Google Shopping / Google Product Category' => nil,
  'SEO Title' => nil,
  'SEO Description' => nil,
  'Google Shopping / AdWords Grouping' => nil,
  'Google Shopping / AdWords Labels' => nil,
  'Google Shopping / Condition' => nil,
  'Google Shopping / Custom Product' => nil,
  'Google Shopping / Custom Label 0' => nil,
  'Google Shopping / Custom Label 1' => nil,
  'Google Shopping / Custom Label 2' => nil,
  'Google Shopping / Custom Label 3' => nil,
  'Google Shopping / Custom Label 4' => nil,
  'Variant Image' => nil,
  'Variant Weight Unit' => nil,
  'Collection' => nil
}
def run
  reload
  process
end

def process filename=INPUT_FILENAME
  table = open_csv_table(filename)
  table = sort_main_variant(table)
  write_table table, 'sorted.csv'

  delete_nonpublished_products(table)
  cleanup_product_names(table)
  swap_sale_prices(table)
  extract_categories(table)
  cleanup_tags(table)

  duplicate_columns(table, [['Featured Image', 'Image Src'], ['Description', 'SEO Description'], ['Product Name', 'SEO Title'], ['Category', 'Collection']] )
  # wordpress stores all images in the image gallery and has a separate featured image field which is one of the gallery images
  concatenate_image_src_from_gallery(table)
  populate_field_for_child_variants(table, 'Slug', proc{ |row| old_format_main_variant(row) } )
  remove_fields_for_child_variants(table, ['Image Src', 'Category', 'Collection'], proc{ |row| old_format_main_variant(row) })
  move_fields_down(table, ['Product SKU', 'Product Name', 'Description', 'Tag', 'Image Src', 'Category', 'Collection'])
  remove_first_variant(table)

  table = rename_headers(table)
  write_table table, 'input.csv'

  output_table = build_output_table(table)
  output_table = expand_image_src(output_table)
  populate_field_for_child_variants(output_table, 'Handle', proc{ |row| new_format_main_variant(row) } )
  remove_fields_for_child_variants(output_table, ['Gift Card', 'Published'], proc{ |row| new_format_main_variant(row) })
  remove_unused_option_names(output_table)
  shift_options_forward(output_table)
  write_table(output_table, 'table.csv')
end

def open_csv_table filename
  CSV.read( filename, { headers:           true,
                    converters:        :numeric,
                    header_converters: nil } )
end

def delete_nonpublished_products table
  populate_field_for_child_variants(table, 'Product Status', proc{ |row| old_format_main_variant(row) })
  table.delete_if { |row| row["Product Status"] != "Publish" }
end

def cleanup_product_names table
  table["Product Name"] = table["Product Name"].map { |name| name.index("Variation") ? nil : name }
end

def swap_sale_prices table
  table.each do |row|
    if sale_price = row['Sale Price']
      row['Sale Price'] = row['Price']
      row['Price'] = sale_price
    end
  end
end

def move_down column_array
  prev_value = column_array[0]

  column_array.map do |current_value|
    previous_value = prev_value
    prev_value = current_value
    !previous_value.nil? && current_value.nil? ? previous_value : current_value
  end
end

def shift_options_forward table
  table.each do |row|
    if row['Option1 Name'].nil? && row['Option2 Name']
      row['Option1 Name'] = row['Option2 Name']
      row['Option1 Value'] = row['Option2 Value']
      row['Option2 Name'] = nil
      row['Option2 Value'] = nil
    end
  end
end

def build_output_table table
  new_table_rows = []
  table.count.times { new_table_rows << CSV::Row.new(HEADERS.keys, HEADERS.values).dup }
  output_table = CSV::Table.new(new_table_rows)
  output_table.by_col!

  HEADERS.each_with_index do |(header, default_value), index|
    output_table[index] = table[header] if table.headers.include? header
  end

  output_table.by_row!
  output_table
end

def sort_main_variant(table)
  duplicate_column(table, 'Product ID', 'Parent ID')

  sorted_table = table.sort_by do |row|
    [row["Parent ID"].to_i, -(row["Product ID"].to_i)]
  end.reverse

  CSV::Table.new(sorted_table)
end

def write_table table, filename
  File.open(filename, 'w') do |f|
    f.write table
  end
end

def move_fields_down(table, fields)
  fields.each do |field|
    table[field] = move_down(table[field])
  end
end

def extract_category string
  return unless string

  arr = string
    .gsub('NEW', '')
    .gsub('SALE', '')
    .gsub('>', '|')
    .gsub(' ', '|')
    .split('|')

  arr -= ['']

  arr.each do |cat|
    return cat if cat == cat.upcase
  end
end

def duplicate_column!(table, old_column, new_column)
 table[new_column] = table[old_column]
end

def duplicate_column(table, old_column, new_column)
  table.each do |row|
    if row[new_column].nil?
      row[new_column] = row[old_column]
    end
  end
end

def duplicate_columns(table, column_array)
  column_array.each { |old_new_columns| duplicate_column!(table, *old_new_columns) }
end

def remove_first_variant(table)
  table.delete_if { |row| old_format_main_variant(row) }
end

def extract_categories(table)
  table["Category"] = table["Category"].map(&method(:extract_category))
end

def remove_fields_for_child_variants(table, column_names, main_variant_proc)
  column_names.each do |column_name|
    table.each do |row|
      row[column_name] = nil unless main_variant_proc.(row)
    end
  end
end

def concatenate_image_src_from_gallery(table)
  table['Image Src'] =
    table['Image Src']
      .zip(table['Product Gallery'])
      .map(&:compact)
      .map { |urls| urls.join('|') }
end

def expand_image_src(table)
  process_as_array(table) do |csv_array|
    empty_row = csv_array.first.map { |r| nil }
    image_src_col_num = 24

    csv_array.each_with_index do |row, index|
      if index > 0 && row[image_src_col_num]
        urls = row[image_src_col_num].split('|')

        additional_urls = urls[1..-1]
        if additional_urls
          additional_urls.reject! { |url| url == urls[0] }

          additional_urls.each do |additional_url|
            new_row = empty_row.dup
            new_row[image_src_col_num] = additional_url
            csv_array.insert(index + 1, new_row)
          end

          row[image_src_col_num] = urls[0]
        end
      end
    end
  end
end


def populate_field_for_child_variants(table, column_name, main_variant_proc)
  main_variant_value = nil

  table.each do |row|
    if main_variant_proc.(row)
      main_variant_value = row[column_name]
    else
      row[column_name] = main_variant_value
    end
  end
end

def old_format_main_variant(row)
  row["Parent SKU"].nil?
end

def new_format_main_variant(row)
  !(row["Title"].nil?)
end

def cleanup_tags(table)
  table["Tag"] = table["Tag"].map do |t|
    t && t.split('|')
      .map(&:capitalize)
      .join(',')
  end
end

def rename_headers(table)
  process_as_array(table) do |csv_array|
    header_row = csv_array.first

    RENAME_HEADERS.each do |old_header, new_header|
      header_row[header_row.index(old_header)] = new_header
    end
  end
end

def process_as_array table
  table_arr = table.to_a

  yield table_arr

  to_table(table_arr)
end

def to_table array
  csv_rows = array[1..-1].map { |row| CSV::Row.new(array.first, row) }
  CSV::Table.new(csv_rows)
end

def remove_unused_option_names table
  ["Option1", "Option2"].each do |option|
    table.each do |row|
      row["#{option} Name"] = nil if row["#{option} Value"].nil?
    end
  end
end

def reload
  load 'transform.rb'
end
