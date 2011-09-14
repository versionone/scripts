$LOAD_PATH <<File.expand_path('..',__FILE__)
require 'rake'
require 'fileutils'
require 'db_backup'


@build = ENV['BUILD_NUMBER'] || 0
@sqlserver_name = ".\\MSSQLSERVER_R2"
@host_name = "localhost"

@exception_logs = "C:/ProgramData/VersionOne/Exceptions/*.log"
@core_setup_10_3 = FileList["VersionOne.Setup-Enterprise-10.3*.exe"].last
@core_setup_11_0 = FileList["VersionOne.Setup-Ultimate-11.0*.exe"].last
@core_setup_11_1 = FileList["VersionOne.Setup-Enterprise-11.1*.exe"].last
@core_setup_11_2 = FileList["VersionOne.Setup-Ultimate-11.2*.exe"].last

@core_instance= "Enterprise"
@ideas_instance = "InnovationsEnt"


task :upgrade10_3 => [:restore_db, :install10_3, :upgrade, :uninstall]
task :upgrade11_0 => [:restore_db, :install11_0, :upgrade, :uninstall]
task :upgrade11_1 => [:restore_db, :install11_1, :upgrade, :uninstall]


desc "Restores a fresh Core database"
task :restore_db do 
  backup_file = File.expand_path("../CoreFunctionalTests/CITestData/#{@core_instance}.bak", __FILE__)
  restore_db :server => @sqlserver_name, :name => @core_instance, :files => DB_Files[:core]
end

desc "Installs 10.3 Core with a database backup "
task :install10_3 => [:restore_db] do
  sh "#{@core_setup_10_3} -quiet -DBServer=#{@sqlserver_name} -DBName=#{@core_instance} -Hosted #{@core_instance}"
  install_license @core_instance
  iis_reset
end


desc "Installs 11 Core with a database backup "
task :install11_0 => [:restore_db] do
  sh "#{@core_setup_11_0} -quiet -DBServer=#{@sqlserver_name} -DBName=#{@core_instance} -Hosted #{@core_instance}"
  install_license @core_instance
  iis_reset
end


desc "Installs 11.1 Core with a database backup "
task :install11_1 => [:restore_db] do
  sh "#{@core_setup_11_1} -quiet -DBServer=#{@sqlserver_name} -DBName=#{@core_instance} -Hosted #{@core_instance}"
  install_license @core_instance
  iis_reset
end


desc "Installs 11.2 Core with a database backup "
task :install11_2 => [:restore_db] do
  sh "#{@core_setup_11_2} -quiet -DBServer=#{@sqlserver_name} -DBName=#{@core_instance} -Hosted #{@core_instance}"
  install_license @core_instance
  iis_reset
end

desc "Uninstalls the Core instance."
task :uninstall do 
  begin
    sh "#{@core_setup_11_2} -u -quiet -DeleteDatabase #{@core_instance}"
  rescue
    puts "No Core Instances to uninstall!"
  end
end


desc "Upgrade current version to Enterprise to 11.2"
task :upgrade do
  begin
    sh "#{@core_setup_11_2} -quiet -r #{@core_instance}"
  rescue
    puts "Upgrade FAILED"

  end
end



def iis_reset
  sh "iisreset"
end

def install_license(instance)
  cp "VersionOne.Dev.Lic", File.join(ENV['SystemDrive'], 'inetpub', 'wwwroot', instance, 'bin')
end

def restore_db(db)
  sql_data = mkdir_p File.join(ENV['SystemDrive'], 'SqlData')
  files = db[:files]
  mdf = File.join(sql_data, "#{files[:data]}.mdf").gsub('/','\\') # SqlCmd requires Windows slashes.
  ldf = File.join(sql_data, "#{files[:log]}.ldf").gsub('/','\\')
  sysft = File.join(sql_data, "#{files[:full_text]}.fts").gsub('/','\\')

  cmd = %{ RESTORE DATABASE #{db[:name]} FROM DISK = '#{files[:backup]}' WITH REPLACE, }
  cmd << %{ MOVE '#{files[:data]}' TO '#{mdf}', MOVE '#{files[:log]}' TO '#{ldf}' }
  cmd << %{, MOVE '#{files[:full_text]}' TO '#{sysft}'} if files[:full_text]

  sh %{sqlcmd -S #{db[:server]} -Q "#{cmd}"}, :verbose => true

end


def  attach_exception_log
  Dir.glob(@exception_logs).each {|x|
    cp x, "exception.log"
	rm_rf x if File.exist?(x)
	puts "Exceptions log generated during test run!"
    #@tests_pass = false    
	}
end






def merge_defaults(options)
  @props.merge(options)
end

def setup_defaults

  @props = {}

  @props[:tools_msbuild] = 'C:\\WINDOWS\\Microsoft.NET\\Framework\\v3.5\\MSBuild.exe'
  @props[:tools_mstest] = 'mstest'

  @props[:build_rebuild] = true
  @props[:build_config] = :release 
end

setup_defaults


