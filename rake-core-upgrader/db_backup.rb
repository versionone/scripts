DB_Files = {
  :core => {
    :backup => File.expand_path('../CoreFunctionalTests/CITestData/Enterprise.bak', __FILE__),
    :data => 'Enterprise',
    :log => 'Enterprise_log',
    :full_text => 'ftrow_DefaultFulltextCatalog'
  },
    :team => {
    :backup => File.expand_path('../CoreFunctionalTests/CITestData/TeamDemoData.bak', __FILE__),
    :data => 'V1Demo',
    :log => 'V1Demo_log',
    :full_text => 'sysft_DefaultFulltextCatalog'
  },
  :analytics => {
    :backup => File.expand_path('../AnalyticsFunctionalTests/CITestData/VersionOne.bak', __FILE__),
    :data => 'V1Test',
    :log => 'V1Test_log',
    :full_text => 'V1Test_ftrow_DefaultFulltextCatalog'
  },
  :ideas => {
    :backup => File.expand_path('../CoreFunctionalTests/CITestData/InnovationsEnt.bak', __FILE__),
    :data => 'InnovationsEnt',
    :log => 'InnovationsEnt_log'
  }
}
