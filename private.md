my credentional:
PS C:\Users\Admin> az account list --output table
Name                  CloudName    SubscriptionId                        TenantId                              State    IsDefault
--------------------  -----------  ------------------------------------  ------------------------------------  -------  -----------
Azure subscription 1  AzureCloud   80d5ca11-41c3-45bb-832f-434c4b25b875  b982394e-41b5-447c-8a7a-40b5ad725bba  Enabled  True

PS C:\Users\Admin> az account show --output table
EnvironmentName    HomeTenantId                          IsDefault    Name                  State    TenantDefaultDomain                   TenantDisplayName     TenantId
-----------------  ------------------------------------  -----------  --------------------  -------  ------------------------------------  --------------------  ------------------------------------
AzureCloud         b982394e-41b5-447c-8a7a-40b5ad725bba  True         Azure subscription 1  Enabled  nikita1lipovichgmail.onmicrosoft.com  Каталог по умолчанию  b982394e-41b5-447c-8a7a-40b5ad725bba