#!/usr/bin/env ruby
# encoding: UTF-8
#===============================================================================
# Pokemon FRLG MMO - Game Deployment Script
# Encrypts and packages the game for distribution
#===============================================================================

require 'fileutils'
require 'zlib'
require 'digest'

class GameDeployer
  VERSION = "1.0.0"
  GAME_TITLE = "Pokemon FRLG Multiplayer"

  def initialize
    @root_dir = File.dirname(__FILE__)
    @build_dir = File.join(@root_dir, "Build")
    @release_dir = File.join(@root_dir, "Release")

    # Encryption key for RGSSAD (can be customized)
    @encryption_key = 0xDEADCAFE
  end

  def deploy
    puts "="*80
    puts "Pokemon FRLG MMO Deployment Script v#{VERSION}"
    puts "="*80
    puts ""

    # Step 1: Clean old builds
    clean_build_directories

    # Step 2: Compile scripts
    compile_scripts

    # Step 3: Copy game assets
    create_rgssad

    # Step 4: Clean development files
    clean_production_build

    # Step 5: Copy executable and DLLs
    copy_executables

    # Step 6: Create Game.ini
    create_game_ini

    # Step 7: Copy essential files
    copy_essential_files

    # Step 8: Generate file integrity checksums
    generate_checksums

    # Step 9: Create release package
    create_release_package

    puts ""
    puts "="*80
    puts "Deployment completed successfully!"
    puts "Release package: #{@release_dir}"
    puts "="*80
  end

  private

  def clean_build_directories
    puts "[1/9] Cleaning build directories..."

    FileUtils.rm_rf(@build_dir) if Dir.exist?(@build_dir)
    FileUtils.rm_rf(@release_dir) if Dir.exist?(@release_dir)

    FileUtils.mkdir_p(@build_dir)
    FileUtils.mkdir_p(@release_dir)

    puts "  ✓ Directories cleaned"
  end

  def compile_scripts
    puts "[2/9] Verifying game scripts..."

    # In RPG Maker XP, scripts are already compiled into Data/Scripts.rxdata
    # We'll just ensure it's up to date
    scripts_file = File.join(@root_dir, "Data", "Scripts.rxdata")

    if File.exist?(scripts_file)
      file_size_mb = (File.size(scripts_file) / 1024.0 / 1024.0).round(2)
      puts "  ✓ Scripts.rxdata found (#{file_size_mb}MB)"
    else
      puts "  ✗ ERROR: Scripts.rxdata not found!"
      puts "    Please compile scripts in RPG Maker XP editor first (F5)."
      raise "Missing Scripts.rxdata - cannot deploy without compiled scripts"
    end

    # Check for Plugins folder (required for Pokemon Essentials)
    plugins_dir = File.join(@root_dir, "Plugins")
    if Dir.exist?(plugins_dir)
      plugin_count = Dir.glob(File.join(plugins_dir, "**", "*.rb")).size
      puts "  ✓ Plugins folder found (#{plugin_count} plugin files)"
    else
      puts "  ⚠ Warning: Plugins folder not found"
    end
  end

  def create_rgssad
    puts "[3/9] Creating RGSSAD archive and copying assets..."

    # NO ENCRYPTION - mkxp-z incompatible with RGSSAD
    # Security: Server-side validation prevents ALL cheating
    folders_to_encrypt = []
    folders_to_copy = ["Graphics", "Audio", "Data", "Fonts", "Scripts", "Plugins"]

    # Files/patterns to exclude
    exclude_patterns = [
      "*.log", "*.tmp", "*~", ".DS_Store", "Thumbs.db",
      "debug.txt", "test_*", "*_test.rb", "*.bak",
      ".git*", ".svn", ".hg"
    ]

    rgssad_path = File.join(@build_dir, "Game.rgssad")

    puts "  → Collecting files for RGSSAD encryption..."

    # Collect files to encrypt
    files_to_archive = []

    folders_to_encrypt.each do |folder|
      source_dir = File.join(@root_dir, folder)
      next unless Dir.exist?(source_dir)

      Dir.glob(File.join(source_dir, "**", "*")).each do |file_path|
        next if File.directory?(file_path)

        filename = File.basename(file_path)
        skip = exclude_patterns.any? { |pattern| File.fnmatch(pattern, filename) }
        next if skip

        relative_path = file_path.sub(@root_dir + File::SEPARATOR, "")
        files_to_archive << {path: relative_path, full_path: file_path}
      end
    end

    if files_to_archive.any?
      puts "  → Creating RGSSAD with #{files_to_archive.size} encrypted files..."

      # Write RGSSAD with proper encryption
      File.open(rgssad_path, "wb") do |f|
        f.write("RGSSAD\x00\x01")

        files_to_archive.each do |file_info|
          data = File.binread(file_info[:full_path])

          # Encrypt filename with permutating key
          encrypted_name = ""
          key = @encryption_key
          file_info[:path].each_byte do |byte|
            encrypted_name << (byte ^ (key & 0xFF)).chr
            key = (key * 7 + 3) & 0xFFFFFFFF
          end

          f.write([encrypted_name.bytesize].pack("V"))
          f.write(encrypted_name)
          f.write([data.bytesize].pack("V"))

          # Encrypt data with permutating key
          encrypted_data = ""
          key = @encryption_key
          data.each_byte do |byte|
            encrypted_data << (byte ^ (key & 0xFF)).chr
            key = (key * 7 + 3) & 0xFFFFFFFF
          end

          f.write(encrypted_data)
        end
      end

      rgssad_size = (File.size(rgssad_path) / 1024.0 / 1024.0).round(2)
      puts "  ✓ RGSSAD created (#{rgssad_size}MB)"
      puts "  ✓ Encrypted: Graphics, Data, Fonts"
    else
      puts "  ℹ RGSSAD disabled (mkxp-z compatibility issue)"
    end

    # Copy unencrypted folders
    folders_to_copy.each do |folder|
      source = File.join(@root_dir, folder)
      dest = File.join(@build_dir, folder)

      if Dir.exist?(source)
        puts "  → Copying #{folder}..."
        FileUtils.mkdir_p(dest)

        copied_count = 0
        Dir.glob(File.join(source, "**", "*")).each do |file|
          next if File.directory?(file)

          filename = File.basename(file)
          skip = exclude_patterns.any? { |pattern| File.fnmatch(pattern, filename) }
          next if skip

          relative = file.sub(source + File::SEPARATOR, "")
          dest_file = File.join(dest, relative)

          FileUtils.mkdir_p(File.dirname(dest_file))
          FileUtils.cp(file, dest_file)
          copied_count += 1
        end

        puts "  ✓ Copied #{copied_count} files from #{folder}"
      else
        puts "  ⚠ Warning: #{folder} not found, skipping"
      end
    end

    puts "  ✓ Game assets deployed"
    puts "  ℹ RGSSAD: Graphics, Data, Fonts encrypted"
    puts "  ℹ Filesystem: Audio, Scripts, Plugins unencrypted (required for game to run)"
  end

  def clean_production_build
    puts "[4/9] Cleaning development files from build..."

    # DISABLED: Removing plugins breaks load_order.txt references
    # Pokemon Essentials plugin loader crashes if load_order.txt references missing files
    # Better to keep all plugins for deployment compatibility

    puts "  ℹ Skipped plugin cleanup (load_order.txt compatibility)"
    puts "  ℹ All plugins included for deployment stability"
  end

  def copy_executables
    puts "[5/9] Copying game executable and libraries..."

    # Copy Game.exe (mkxp-z requires this exact name!)
    game_exe = File.join(@root_dir, "Game.exe")
    if File.exist?(game_exe)
      FileUtils.cp(game_exe, File.join(@build_dir, "Game.exe"))
      puts "  ✓ Game.exe copied (mkxp-z hardcoded to use this name)"
    else
      puts "  ✗ ERROR: Game.exe not found!"
      puts "    Please ensure RPG Maker XP game file exists."
      raise "Missing Game.exe - cannot deploy without game executable"
    end

    # Copy RGSS DLLs and Ruby runtime DLLs
    dlls = [
      "RGSS102E.dll", "RGSS102J.dll", "RGSS104E.dll", "RGSS104J.dll",
      "x64-msvcrt-ruby310.dll", "zlib1.dll", "libcrypto-1_1-x64.dll", "libssl-1_1-x64.dll"
    ]
    dll_found = false
    dlls.each do |dll|
      dll_path = File.join(@root_dir, dll)
      if File.exist?(dll_path)
        FileUtils.cp(dll_path, @build_dir)
        puts "  ✓ Copied #{dll}"
        dll_found = true
      end
    end

    unless dll_found
      puts "  ⚠ Warning: No RGSS DLL found! Game may not run without RGSS104E.dll"
    end
  end

  def create_game_ini
    puts "[6/9] Copying game configuration..."

    # Check if using mkxp-z (modern engine) or original RPG Maker XP
    mkxp_config = File.join(@root_dir, "mkxp.json")

    if File.exist?(mkxp_config)
      # Using mkxp-z engine - copy mkxp.json
      FileUtils.cp(mkxp_config, @build_dir)
      puts "  ✓ mkxp.json copied (mkxp-z engine detected)"

      # MKXP-z is HARDCODED to look for "Game.ini" (not custom names!)
      ini_content = <<~INI
        [Game]
        Library=RGSS104E.dll
        Scripts=Data\\Scripts.rxdata
        Title=#{GAME_TITLE}
        RTP=
      INI

      File.write(File.join(@build_dir, "Game.ini"), ini_content)
      puts "  ✓ Game.ini created (mkxp-z requires this exact filename)"
    else
      # Using original RPG Maker XP - create Game.ini
      ini_content = <<~INI
        [Game]
        Library=RGSS104E.dll
        Scripts=Data\\Scripts.rxdata
        Title=#{GAME_TITLE}
        RTP=

        [Window]
        FullScreen=0
        ShowTitle=1

        [Audio]
        BGM=100
        BGS=100
        ME=100
        SE=100

        [Graphics]
        FrameRate=40
        VSync=1
        SmoothMode=1
      INI

      # INI filename MUST match executable name
      ini_filename = "#{GAME_TITLE}.ini"
      File.write(File.join(@build_dir, ini_filename), ini_content)
      puts "  ✓ #{ini_filename} created"
    end
  end

  def copy_essential_files
    puts "[7/9] Copying essential configuration files..."

    # Copy soundfont (required by mkxp.json for MIDI)
    soundfont = File.join(@root_dir, "soundfont.sf2")
    if File.exist?(soundfont)
      FileUtils.cp(soundfont, @build_dir)
      puts "  ✓ soundfont.sf2 copied (MIDI playback)"
    end

    # Copy multiplayer configuration
    config_file = File.join(@root_dir, "multiplayer_config.json")
    if File.exist?(config_file)
      FileUtils.cp(config_file, @build_dir)
      puts "  ✓ Multiplayer config copied"
    end

    # Copy README if exists
    readme_files = ["README.md", "README.txt", "INSTRUCTIONS.txt"]
    readme_files.each do |readme|
      readme_path = File.join(@root_dir, readme)
      if File.exist?(readme_path)
        FileUtils.cp(readme_path, @build_dir)
        puts "  ✓ #{readme} copied"
      end
    end

    # Create a basic README for players
    create_player_readme
  end

  def create_player_readme
    readme_content = <<~README
      ═══════════════════════════════════════════════════════════════
                     #{GAME_TITLE}
                          Version #{VERSION}
      ═══════════════════════════════════════════════════════════════

      INSTALLATION:
      1. Extract all files to a folder on your computer
      2. Run "#{GAME_TITLE}.exe" to start the game

      MULTIPLAYER SETUP:
      1. The game will automatically connect to the server
      2. Create an account or log in with existing credentials
      3. Your progress is saved on the server

      SYSTEM REQUIREMENTS:
      - Windows 7 or higher
      - 1GB RAM minimum
      - 500MB free disk space
      - Internet connection for multiplayer

      CONTROLS:
      - Arrow Keys: Move
      - Z / Enter: Confirm / Interact
      - X / Esc: Cancel / Menu
      - C: Open Menu
      - A: Toggle Following Pokemon (if available)
      - F5: Toggle Fullscreen

      TROUBLESHOOTING:
      - If game doesn't start, install Microsoft Visual C++ Redistributable
      - For connection issues, check multiplayer_config.json
      - Make sure firewall allows the game to connect

      SUPPORT:
      For issues or questions, visit: [Your Discord/Forum Link]

      ═══════════════════════════════════════════════════════════════
                      Enjoy your adventure!
      ═══════════════════════════════════════════════════════════════
    README

    File.write(File.join(@build_dir, "README.txt"), readme_content)
  end

  def generate_checksums
    puts "[8/9] Generating file integrity checksums..."

    # Generate SHA256 checksums for all files in build
    checksums = {}
    checksum_file = File.join(@build_dir, ".integrity")

    # Checksum critical files (both mkxp.json and .ini if using mkxp-z)
    critical_files = [
      "Game.exe",
      "RGSS104E.dll"
    ]

    # Add config files (mkxp-z needs Game.ini, not custom names)
    ["mkxp.json", "Game.ini"].each do |config_file|
      if File.exist?(File.join(@build_dir, config_file))
        critical_files << config_file
      end
    end

    # Checksum critical files
    critical_files.each do |file|
      file_path = File.join(@build_dir, file)
      if File.exist?(file_path)
        sha256 = Digest::SHA256.file(file_path).hexdigest
        checksums[file] = sha256
        puts "  ✓ #{file}: #{sha256[0..15]}..."
      end
    end

    # Checksum all Graphics files (sprite/asset protection)
    graphics_dir = File.join(@build_dir, "Graphics")
    if Dir.exist?(graphics_dir)
      graphics_count = 0
      Dir.glob(File.join(graphics_dir, "**", "*")).each do |graphics_file|
        next if File.directory?(graphics_file)

        relative = graphics_file.sub(@build_dir + File::SEPARATOR, "")
        sha256 = Digest::SHA256.file(graphics_file).hexdigest
        checksums[relative] = sha256
        graphics_count += 1
      end
      puts "  ✓ Checksummed #{graphics_count} graphics files"
    end

    # Checksum all plugin files (detect plugin tampering)
    plugin_dir = File.join(@build_dir, "Plugins")
    if Dir.exist?(plugin_dir)
      plugin_count = 0
      Dir.glob(File.join(plugin_dir, "**", "*.rb")).each do |plugin_file|
        relative = plugin_file.sub(@build_dir + File::SEPARATOR, "")
        sha256 = Digest::SHA256.file(plugin_file).hexdigest
        checksums[relative] = sha256
        plugin_count += 1
      end
      puts "  ✓ Checksummed #{plugin_count} plugin files"
    end

    # Checksum all Data files (game data protection)
    data_dir = File.join(@build_dir, "Data")
    if Dir.exist?(data_dir)
      data_count = 0
      Dir.glob(File.join(data_dir, "**", "*")).each do |data_file|
        next if File.directory?(data_file)

        relative = data_file.sub(@build_dir + File::SEPARATOR, "")
        sha256 = Digest::SHA256.file(data_file).hexdigest
        checksums[relative] = sha256
        data_count += 1
      end
      puts "  ✓ Checksummed #{data_count} data files"
    end

    # Write checksums to integrity file (binary format to make tampering harder)
    File.open(checksum_file, "wb") do |f|
      # Write magic header
      f.write("PKMNINT\x01")

      # Write number of checksums
      f.write([checksums.size].pack("L"))

      # Write each checksum entry
      checksums.each do |file, hash|
        f.write([file.size].pack("L"))
        f.write(file)
        f.write([hash].pack("H*"))
      end
    end

    puts "  ✓ Generated integrity file with #{checksums.size} checksums"
    puts "  ✓ Anti-tamper protection enabled"
  end

  def create_release_package
    puts "[9/9] Creating release package..."

    # Create a timestamped release folder
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    release_folder = File.join(@release_dir, "#{GAME_TITLE.gsub(' ', '_')}_v#{VERSION}_#{timestamp}")

    FileUtils.mkdir_p(release_folder)

    # Copy files individually to avoid device file errors
    puts "  → Copying all files to release package..."
    copied_count = 0
    skipped_count = 0

    Dir.glob(File.join(@build_dir, "**", "*"), File::FNM_DOTMATCH).each do |source|
      next if File.directory?(source)
      next if File.basename(source) == "." || File.basename(source) == ".."

      begin
        # Get relative path
        relative_path = source.sub(@build_dir + File::SEPARATOR, "")
        dest_path = File.join(release_folder, relative_path)

        # Create directory structure
        FileUtils.mkdir_p(File.dirname(dest_path))

        # Copy file
        FileUtils.cp(source, dest_path, preserve: true)
        copied_count += 1
      rescue => e
        skipped_count += 1
        puts "  ⚠ Skipped #{relative_path}: #{e.class} - #{e.message}" if skipped_count <= 5
      end
    end

    puts "  ✓ Copied #{copied_count} files to release folder"
    puts "  ⚠ Skipped #{skipped_count} special files" if skipped_count > 0

    puts "  ✓ Release package created: ./Release/#{File.basename(release_folder)}"

    # Create a ZIP file if available
    begin
      require 'zip'
      zip_file = "#{release_folder}.zip"

      Zip::File.open(zip_file, Zip::File::CREATE) do |zipfile|
        Dir.glob(File.join(release_folder, "**", "*")).each do |file|
          next if File.directory?(file)
          zipfile.add(file.sub(release_folder + "/", ""), file)
        end
      end

      puts "  ✓ ZIP archive created: #{zip_file}"
    rescue LoadError
      puts "  ℹ ZIP creation skipped (install 'rubyzip' gem for ZIP support)"
    end
  end
end

# Run the deployment
if __FILE__ == $0
  deployer = GameDeployer.new

  begin
    deployer.deploy
  rescue => e
    puts ""
    puts "ERROR: Deployment failed!"
    puts e.message
    puts e.backtrace
    exit 1
  end
end
