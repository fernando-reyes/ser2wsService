object AppService: TAppService
  OldCreateOrder = False
  OnCreate = UniGUIServiceCreate
  DisplayName = 'ser2wsService'
  ServiceStartName = 'NT AUTHORITY\SYSTEM'
  AfterInstall = UniGUIServiceAfterInstall
  Height = 150
  Width = 215
end
