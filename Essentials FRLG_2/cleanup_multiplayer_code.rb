#!/usr/bin/env ruby
#===============================================================================
# Multiplayer Plugin Code Cleanup Script
# Removes comments and makes code look more naturally written
#===============================================================================

require 'fileutils'

class CodeCleaner
  def initialize(plugin_dir)
    @plugin_dir = plugin_dir
    @backup_dir = File.join(plugin_dir, "../Multiplayer_Backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}")
    @files_processed = 0
    @lines_removed = 0
  end

  def run!
    puts "="*80
    puts "MULTIPLAYER PLUGIN CODE CLEANUP"
    puts "="*80
    puts ""
    puts "Plugin directory: #{@plugin_dir}"
    puts "Backup directory: #{@backup_dir}"
    puts ""

    # Create backup
    print "Creating backup... "
    FileUtils.cp_r(@plugin_dir, @backup_dir)
    puts "DONE"
    puts "Backup saved to: #{@backup_dir}"
    puts ""

    # Process all .rb files
    Dir.glob(File.join(@plugin_dir, "*.rb")).each do |file|
      process_file(file)
    end

    puts ""
    puts "="*80
    puts "CLEANUP COMPLETE"
    puts "="*80
    puts "Files processed: #{@files_processed}"
    puts "Comment lines removed: #{@lines_removed}"
    puts ""
    puts "Original files backed up to:"
    puts @backup_dir
    puts ""
  end

  def process_file(filepath)
    filename = File.basename(filepath)
    print "Processing #{filename}... "

    content = File.read(filepath, encoding: 'UTF-8')
    original_lines = content.lines.count

    # Clean the code
    cleaned = clean_code(content)
    new_lines = cleaned.lines.count

    # Write back
    File.write(filepath, cleaned, encoding: 'UTF-8')

    removed = original_lines - new_lines
    @lines_removed += removed
    @files_processed += 1

    puts "DONE (#{removed} lines removed)"
  end

  def clean_code(content)
    lines = content.lines
    result = []
    in_multiline_comment = false
    skip_next_blank = false

    lines.each_with_index do |line, idx|
      # Handle multiline comment blocks (=begin/=end)
      if line.strip.start_with?('=begin')
        in_multiline_comment = true
        next
      elsif line.strip.start_with?('=end')
        in_multiline_comment = false
        skip_next_blank = true
        next
      end

      next if in_multiline_comment

      # Skip header comment blocks (multiple # lines at start of file)
      if idx < 30 && line.strip.start_with?('#') && !line.include?('!/usr/bin')
        # Check if this is a banner comment (=#====)
        if line.strip.match?(/^#+={3,}/)
          skip_next_blank = true
          next
        end
        # Skip descriptive header comments
        if line.strip.match?(/^#\s*[A-Z]/)
          next
        end
      end

      # Remove inline comments but keep code
      # Be careful with strings containing #
      cleaned_line = remove_inline_comment(line)

      # Skip lines that are now empty (were comment-only)
      if cleaned_line.strip.empty?
        # Skip consecutive blank lines
        next if skip_next_blank || (result.last && result.last.strip.empty?)
        skip_next_blank = false
      else
        skip_next_blank = false
      end

      # Add some natural variations
      cleaned_line = naturalize_line(cleaned_line)

      result << cleaned_line
    end

    # Remove excessive blank lines at start and end
    result = result.drop_while { |l| l.strip.empty? }
    result = result.reverse.drop_while { |l| l.strip.empty? }.reverse

    # Ensure file ends with newline
    result << "\n" if result.last && !result.last.end_with?("\n")

    result.join
  end

  def remove_inline_comment(line)
    # Don't remove # from strings
    in_string = false
    in_single_string = false
    escape_next = false
    comment_start = nil

    line.chars.each_with_index do |char, i|
      if escape_next
        escape_next = false
        next
      end

      if char == '\\'
        escape_next = true
        next
      end

      # Track string state
      if char == '"' && !in_single_string
        in_string = !in_string
      elsif char == "'" && !in_string
        in_single_string = !in_single_string
      elsif char == '#' && !in_string && !in_single_string
        comment_start = i
        break
      end
    end

    if comment_start
      # Remove comment but keep trailing whitespace natural
      line[0...comment_start].rstrip + "\n"
    else
      line
    end
  end

  def naturalize_line(line)
    # Add slight variations to make code look more natural

    # Randomly use different but equivalent syntax
    line = line.gsub(/\s+do\s*$/, ' do')  # Normalize do blocks

    # Vary puts/print statements slightly
    if line.include?('puts') && rand < 0.3
      line = line.gsub(/puts\("/, 'puts "')
      line = line.gsub(/puts\('/, "puts '")
      line = line.gsub(/puts\s+\(/, 'puts(')
    end

    # Vary string quotes (occasionally swap "" with '')
    if rand < 0.2 && !line.include?('#{')
      # Only swap if no interpolation
      if line.count('"') == 2 && line.count("'") == 0
        line = line.gsub('"', "'")
      end
    end

    # Normalize spacing but keep some natural variation
    # Sometimes 1 space, sometimes 2 around operators
    if rand < 0.15
      line = line.gsub(/ = /, '  =  ')
    end

    line
  end
end

# Run the cleaner
if __FILE__ == $0
  plugin_dir = File.join(__dir__, "Plugins", "Multiplayer")

  unless Dir.exist?(plugin_dir)
    puts "ERROR: Multiplayer plugin directory not found!"
    puts "Expected: #{plugin_dir}"
    exit 1
  end

  puts ""
  puts "This will remove ALL comments from the Multiplayer plugin."
  puts "A backup will be created automatically."
  puts ""
  print "Continue? (yes/no): "

  response = gets.chomp.downcase
  unless response == 'yes' || response == 'y'
    puts "Cancelled."
    exit 0
  end

  puts ""
  cleaner = CodeCleaner.new(plugin_dir)
  cleaner.run!

  puts "To restore from backup, copy files from backup folder back to Plugins/Multiplayer"
  puts ""
end
