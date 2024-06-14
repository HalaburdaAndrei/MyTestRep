public with sharing class TrackingOrganizationController {
    public static Boolean isFirst = true;

    public String sourceId { get; set; }
    public String userSessionId { get; set; }
    public String userInstanceUrl { get; set; }
    public String accessToken { get; set; }
    public String instanceUrl { get; set; }
    public String timeZoneString { get; set; }
    public String lightningDomain { get; set; }

    public TrackingOrganizationController(ApexPages.StandardController controller) {
        sourceId = (String) ApexPages.currentPage().getParameters().get('id');
        userSessionId = UserInfo.getSessionId();
        userInstanceUrl = Url.getOrgDomainUrl().toExternalForm();

        AuthUtils.AuthenticateDetails authDetails = AuthUtils.authenticateAnOrg(sourceId, FlosumConstants.DEVELOPER);
        accessToken = authDetails.details.AccessToken__c;
        instanceUrl = authDetails.details.InstanceURL__c;
        timeZoneString = UserInfo.getTimeZone().toString();
        lightningDomain = FlosumConstants.getLightningDomain();
    }

    @AuraEnabled(Cacheable=true)
    public static String getVisualforceDomain() {
        return FlosumConstants.getVisualforceDomain();
    }

    @AuraEnabled(Cacheable=true)
    public static String getHistoryComparisonUrl() {
        return Page.HistoryComparison.getUrl();
    }

    @AuraEnabled(Cacheable=true)
    public static String getSessionId() {
        return UserInfo.getSessionId();
    }

    @AuraEnabled
    public static String getCommitToBranchInfo() {
        return JSON.serialize(new Map<String, Object>{ 'historyComparisonUrl' => Page.HistoryComparison.getUrl() });
    }

    @AuraEnabled
    public static String getNamespacePrefix() {
        String namespacePrefix;
        String[] classNameParts = String.valueOf(UnlockedPackageController.class).split('\\.', 2);
        if (classNameParts.size() > 1) {
            Type classType = Type.forName(classNameParts[0], classNameParts[1]);
            if (classType == UnlockedPackageController.class) {
                namespacePrefix = classNameParts[0];
            } else {
                namespacePrefix = '';
            }
        } else {
            namespacePrefix = '';
        }

        return namespacePrefix;
    }

    public PageReference openCommitToBranch() {
        PageReference pageReference = Page.OrgComponentToBranchCommit;
        pageReference.setRedirect(true);
        pageReference.getParameters().put('id', sourceId);
        return pageReference;
    }

    @AuraEnabled(Cacheable=true)
    public static String searchBranchLookup(Map<String, Object> dataMap) {
        String searchTerm = (String) dataMap.get('searchTerm');
        String repositoryId = (String) dataMap.get('repositoryId');
        searchTerm = '%' + searchTerm + '%';
        List<Branch__c> branchList = [
            SELECT Id, Branch_Name__c, Name
            FROM Branch__c
            WHERE Branch_Name__c LIKE :searchTerm AND Repository__c = :repositoryId
            ORDER BY CreatedDate DESC
            LIMIT 15
        ];

        List<FlosumUtils.LWCLookupSearchResultWrapper> lookupSearchResultWrapperList = new List<FlosumUtils.LWCLookupSearchResultWrapper>();
        String sObjectTypeName = Branch__c.getSObjectType().getDescribe().name;
        for (Branch__c branch : branchList) {
            lookupSearchResultWrapperList.add(
                new FlosumUtils.LWCLookupSearchResultWrapper(
                    branch.Id,
                    sObjectTypeName,
                    'standard:branch_merge',
                    branch.Branch_Name__c,
                    branch.Name
                )
            );
        }

        System.debug(Url.getSalesforceBaseUrl().toExternalForm());

        return JSON.serialize(lookupSearchResultWrapperList);
    }

    @AuraEnabled
    public static Boolean isSupportedOrgType(Map<String, Object> dataMap) {
        if (!dataMap.containsKey('organizationId')) {
            throw new FlosumException('Field \'organizationId\' not provided!');
        }

        String organizationId = (String) dataMap.get('organizationId');

        List<Organisation__c> organisations = [
            SELECT Organisation_Type__c
            FROM Organisation__c
            WHERE Id = :organizationId
        ];

        if (organisations.isEmpty()) {
            return false;
        }

        return !(new Set<String>{ VeevaConstants.VEEVA_TYPE, MCConstants.TYPE, B2CConstants.TYPE }
            .contains(organisations.get(0).Organisation_Type__c));
    }

    @AuraEnabled
    public static String authorize(Map<String, Object> dataMap) {
        if (dataMap.containsKey('organizationId')) {
            String organizationId = (String) dataMap.get('organizationId');
            if (VeevaService.checkVeevaOrg(organizationId)) {
                return JSON.serialize(new Map<String, Object>{ 'isVeeva' => true });
            }
            AuthUtils.AuthenticateDetails authDetails = AuthUtils.authenticateAnOrg(
                organizationId,
                FlosumConstants.DEVELOPER
            );
            return JSON.serialize(
                new Map<String, Object>{
                    'isSuccess' => authDetails.isSuccess,
                    'accessToken' => authDetails.details.AccessToken__c,
                    'instanceUrl' => authDetails.details.InstanceURL__c,
                    'errorMessage' => authDetails.errorMessage
                }
            );
        } else {
            throw new FlosumException('Field \'organizationId\' not provided!');
        }
    }

    @AuraEnabled
    public static String checkSupportedSourceMember(Map<String, Object> dataMap) {
        String accessToken = (String) dataMap.get('accessToken');
        String instanceUrl = (String) dataMap.get('instanceUrl');

        String sourceMemberQuery = TrackingService.QUERY_SOURCE_MEMBER + '+Limit+1';
        String endpoint = instanceUrl + '/services/data/v51.0/tooling/query/?q=' + sourceMemberQuery;
        HttpResponse httpResponse = TrackingService.callRequest(accessToken, endpoint);
        return JSON.serialize(new Map<String, Object>{ 'isSupported' => httpResponse.getStatusCode() == 200 });
    }

    @AuraEnabled
    public static String getSettings(Map<String, Object> dataMap) {
        if (dataMap.containsKey('organizationId')) {
            String organizationId = (String) dataMap.get('organizationId');
            List<String> metadataTypeOptionList = (List<String>) System.JSON.deserialize(
                (String) dataMap.get('metadataTypeOptionList'),
                List<String>.class
            );

            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Tracking_Setting__c.Metadata_Types__c.getDescribe(),
                        Tracking_Setting__c.Is_Enabled__c.getDescribe(),
                        Tracking_Setting__c.Is_Processed__c.getDescribe(),
                        Tracking_Setting__c.Current_Jobs__c.getDescribe()
                    }
                }
            );
            List<Tracking_Setting__c> trackingOrganizationSettingList = [
                SELECT Metadata_Types__c, Is_Enabled__c, Is_Processed__c, Current_Jobs__c
                FROM Tracking_Setting__c
                WHERE Organization__c = :organizationId
            ];
            Tracking_Setting__c trackingOrganizationSetting;
            if (trackingOrganizationSettingList.isEmpty()) {
                List<Organisation__c> organisationList = [
                    SELECT Id, Organisation_ID__c
                    FROM Organisation__c
                    WHERE Id = :organizationId
                ];
                if (organisationList.isEmpty()) {
                    throw new FlosumException('Not found organization by provided Id!');
                }

                trackingOrganizationSetting = new Tracking_Setting__c();
                trackingOrganizationSetting.Organization__c = organisationList.get(0).Id;
                trackingOrganizationSetting.Source_Organization_Id__c = organisationList.get(0).Organisation_ID__c;
                trackingOrganizationSetting.Metadata_Types__c = String.join(metadataTypeOptionList, ',');
                trackingOrganizationSetting.Current_Jobs__c = null;
                trackingOrganizationSetting.Is_Enabled__c = true;
                trackingOrganizationSetting.Is_Processed__c = false;
                trackingOrganizationSetting.Last_Start_Retrieval__c = Datetime.now();

                DatabaseUtils.insertRecord(
                    trackingOrganizationSetting,
                    new List<Schema.DescribeFieldResult>{
                        Tracking_Setting__c.Organization__c.getDescribe(),
                        Tracking_Setting__c.Metadata_Types__c.getDescribe(),
                        Tracking_Setting__c.Current_Jobs__c.getDescribe(),
                        Tracking_Setting__c.Is_Enabled__c.getDescribe(),
                        Tracking_Setting__c.Is_Processed__c.getDescribe(),
                        Tracking_Setting__c.Last_Start_Retrieval__c.getDescribe()
                    }
                );
            } else {
                trackingOrganizationSetting = trackingOrganizationSettingList.get(0);
            }

            return JSON.serialize(new TrackingService.TrackingOrganizationWrapper(trackingOrganizationSetting));
        } else {
            throw new FlosumException('Field \'organizationId\' not provided!');
        }
    }

    @AuraEnabled
    public static String getMetadataTypeList(Map<String, Object> dataMap) {
        String accessToken = (String) dataMap.get('accessToken');
        String instanceUrl = (String) dataMap.get('instanceUrl');
        List<String> metadataTypeList = new List<String>();
        MetadataService.MetadataPort service = MetadataUtils.createService(accessToken, instanceUrl);
        MetadataService.DescribeMetadataResult describeResult = !Test.isRunningTest()
            ? service.describeMetadata(FlosumConstants.apiversion)
            : (MetadataService.DescribeMetadataResult) JSON.deserialize(
                  TrackingOrganizationControllerTest.METADATA_TYPES_DESCRIBE,
                  MetadataService.DescribeMetadataResult.class
              );

        Set<String> metadataTypeFilterSet = new Set<String>(FlosumConstants.profilePermissionMap.keySet());
        metadataTypeFilterSet.add('CustomLabels');

        Set<String> supportedMetadataTypes = FlosumConstants.getAllMetadataTypes();

        for (MetadataService.DescribeMetadataObject metadataObject : describeResult.metadataObjects) {
            if (supportedMetadataTypes.contains(metadataObject.xmlName)) {
                metadataTypeList.add(metadataObject.xmlName);
                if (FlosumConstants.metadataToFolderMap.containsKey(metadataObject.xmlName)) {
                    String folderName = FlosumConstants.metadataToFolderMap.get(metadataObject.xmlName);
                    if (supportedMetadataTypes.contains(folderName)) {
                        metadataTypeList.add(folderName);
                    }
                }
            }

            // Include child Metadata Types (such as CustomField, ValidationRule etc..)
            if (metadataObject.childXmlNames != null) {
                for (String childXmlName : metadataObject.childXmlNames) {
                    if (childXmlName != null) {
                        if (supportedMetadataTypes.contains(childXmlName)) {
                            metadataTypeList.add(childXmlName);
                        }
                    }
                }
            }
        }
        metadataTypeList.sort();
        return JSON.serialize(metadataTypeList);
    }

    @AuraEnabled
    public static String getRelatedListOrgComponentsId() {
        String baseUrl = Url.getOrgDomainUrl().toExternalForm();
        String accessToken = UserInfo.getSessionId();

        String endpoint =
            baseUrl +
            '/services/data/v51.0/tooling/query/?q=' +
            TrackingService.QUERY_ORG_FIELD_ID_IN_ORG_COMPONENT;
        TrackingService.ApexRestResponseWrapper responseWrapper = TrackingService.callSourceMemberResponse(
            accessToken,
            endpoint
        );

        String relatedListId = '';
        if (!responseWrapper.records.isEmpty()) {
            relatedListId = responseWrapper.records.get(0).Id.substring(0, 15);
        }

        return relatedListId;
    }

    @AuraEnabled
    public static String getSourceMembers(Map<String, Object> dataMap) {
        String accessToken = (String) dataMap.get('accessToken');
        String instanceUrl = (String) dataMap.get('instanceUrl');
        String organizationId = (String) dataMap.get('organizationId');
        String whereClause = (String) dataMap.get('whereClause');
        String nextRecordsUrl = (String) dataMap.get('nextRecordsUrl');

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Organization__c.getDescribe(),
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Name.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Name, Is_Processed__c, Organization__r.Name
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];

        if (!trackingOrganizationSettingList.isEmpty()) {
            String endpoint = instanceUrl;
            if (String.isNotBlank(nextRecordsUrl)) {
                endpoint += nextRecordsUrl;
            } else {
                endpoint += '/services/data/v51.0/tooling/query/?q=' + TrackingService.QUERY_SOURCE_MEMBER;
                if (String.isNotBlank(whereClause)) {
                    if (String.isNotBlank(whereClause)) {
                        endpoint += '+AND+' + whereClause;
                    }
                }
            }
            TrackingService.SourceMemberPacksWrapper packsWrapper = TrackingService.callSourceMemberRecords(
                trackingOrganizationSettingList.get(0).Id,
                accessToken,
                endpoint
            );
            List<TrackingService.SourceMemberWrapper> deletedSourceMemberWrapperList = new List<TrackingService.SourceMemberWrapper>();
            List<TrackingService.SourceMemberWrapper> changedSourceMemberWrapperList = new List<TrackingService.SourceMemberWrapper>();
            for (TrackingService.SourceMemberWrapper sourceMemberWrapper : packsWrapper.changedList) {
                if (sourceMemberWrapper.isDeleted) {
                    deletedSourceMemberWrapperList.add(sourceMemberWrapper);
                } else {
                    changedSourceMemberWrapperList.add(sourceMemberWrapper);
                }
            }
            System.debug('deletedSourceMemberWrapperList: ' + deletedSourceMemberWrapperList);
            if (!deletedSourceMemberWrapperList.isEmpty()) {
                TrackingService.upsertOrgComponentList(
                    deletedSourceMemberWrapperList,
                    trackingOrganizationSettingList.get(0).Id,
                    organizationId
                );
            }
            packsWrapper.changedList = changedSourceMemberWrapperList;
            return JSON.serialize(packsWrapper);
        } else {
            throw new FlosumException('Tracking Setting by organization id not found.');
        }
    }

    @AuraEnabled
    public static String getUserNames(Map<String, Object> dataMap) {
        String accessToken = (String) dataMap.get('accessToken');
        String instanceUrl = (String) dataMap.get('instanceUrl');
        String userIds = (String) dataMap.get('userIds');

        String endpoint =
            instanceUrl +
            '/services/data/v52.0/query/?q=SELECT+Id,+Name+FROM+User+WHERE+Id+IN+(' +
            userIds +
            ')';
        HttpResponse httpResponse = TrackingService.callRequest(accessToken, endpoint);
        if (httpResponse.getStatusCode() == 200) {
            return httpResponse.getBody();
        } else {
            throw new FlosumException(httpResponse.getBody());
        }
    }

    @AuraEnabled
    public static void disableTrackingSettings(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Organization__c.getDescribe(),
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Name.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Name, Is_Processed__c, Organization__r.Name
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];
        if (!trackingOrganizationSettingList.isEmpty()) {
            trackingOrganizationSettingList.get(0).Is_Enabled__c = false;
            trackingOrganizationSettingList.get(0).Is_Processed__c = false;
            trackingOrganizationSettingList.get(0).Metadata_Types__c = null;
            trackingOrganizationSettingList.get(0).Current_Apex_Job_Id__c = null;
            trackingOrganizationSettingList.get(0).Current_Jobs__c = null;
            trackingOrganizationSettingList.get(0).Last_Start_Retrieval__c = null;

            DatabaseUtils.updateRecord(
                trackingOrganizationSettingList.get(0),
                new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Is_Enabled__c.getDescribe(),
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Metadata_Types__c.getDescribe(),
                    Tracking_Setting__c.Current_Apex_Job_Id__c.getDescribe(),
                    Tracking_Setting__c.Current_Jobs__c.getDescribe(),
                    Tracking_Setting__c.Last_Start_Retrieval__c.getDescribe()
                }
            );
        }
    }

    @AuraEnabled
    public static String getLatestComponents(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        String lastId = (String) dataMap.get('lastId');
        Boolean isAll = (Boolean) dataMap.get('isAll');
        Boolean isIncludeTooLarge = dataMap.containsKey('isIncludeTooLarge')
            ? (Boolean) dataMap.get('isIncludeTooLarge')
            : false;

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Org_Component__c.Name__c.getDescribe(),
                    Org_Component__c.Component_Type__c.getDescribe(),
                    Org_Component__c.Last_Updated_By__c.getDescribe(),
                    Org_Component__c.Revision_Counter__c.getDescribe(),
                    Org_Component__c.Is_Deleted__c.getDescribe(),
                    Org_Component__c.Last_Modified_Date__c.getDescribe(),
                    Org_Component__c.Status__c.getDescribe(),
                    Org_Component__c.Source_Member_Id__c.getDescribe()
                }
            }
        );
        List<TrackingService.SourceMemberWrapper> sourceMemberWrapperList = new List<TrackingService.SourceMemberWrapper>();
        List<Org_Component__c> updateOrgComponentsStatusList = new List<Org_Component__c>();

        String queryWhere = 'WHERE OrganisationName__c = :organizationId';
        queryWhere += isIncludeTooLarge ? '' : ' AND Attachment_ID__c != \'\'';
        queryWhere += ' AND Status__c IN';
        queryWhere += ' (\'Retrieved\',\'Deleted\',\'Error\'';
        queryWhere += isIncludeTooLarge ? ',\'Too Large\')' : ')';
        queryWhere += String.isNotBlank(lastId) ? ' AND Id > :lastId' : ' ';

        String query = String.format(
            '{0} {1} {2} {3} {4}',
            new List<String>{
                'SELECT Name, Name__c, Component_Type__c, Last_Updated_By__c, Revision_Counter__c, Is_Deleted__c, Last_Modified_Date__c, Status__c, Source_Member_Id__c',
                'FROM Org_Component__c',
                queryWhere,
                'ORDER BY Id',
                isAll ? 'LIMIT 49000' : 'LIMIT 10'
            }
        );

        for (Org_Component__c orgComponent : Database.query(query)) {
            if (orgComponent.Status__c == 'Error') {
                orgComponent.Status__c = 'Retrieved';
                updateOrgComponentsStatusList.add(orgComponent);
            }
            sourceMemberWrapperList.add(new TrackingService.SourceMemberWrapper(orgComponent));
        }
        if (!updateOrgComponentsStatusList.isEmpty()) {
            DatabaseUtils.updateRecords(
                updateOrgComponentsStatusList,
                new List<Schema.DescribeFieldResult>{ Org_Component__c.Status__c.getDescribe() }
            );
        }
        return JSON.serialize(sourceMemberWrapperList);
    }

    @AuraEnabled
    public static String getOrgComponentsForManualRetrieve(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Metadata_Types__c.getDescribe(),
                    Tracking_Setting__c.Is_Enabled__c.getDescribe(),
                    Tracking_Setting__c.Current_Jobs__c.getDescribe(),
                    Tracking_Setting__c.Is_Processed__c.getDescribe()
                }
            }
        );
        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Metadata_Types__c, Is_Enabled__c, Current_Jobs__c, Is_Processed__c
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];
        if (!trackingOrganizationSettingList.isEmpty()) {
            Tracking_Setting__c trackingSetting = trackingOrganizationSettingList.get(0);
            if (!trackingSetting.Is_Processed__c)
                throw new FlosumException('Retrieve is not in the process');
            if (String.isNotBlank(trackingSetting.Current_Jobs__c)) {
                List<OrgComponentWrapper> orgComponentWrapperList = new List<OrgComponentWrapper>();
                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            Org_Component__c.Name.getDescribe(),
                            Org_Component__c.Attachment_ID__c.getDescribe(),
                            Org_Component__c.Last_Updated_By__c.getDescribe(),
                            Org_Component__c.Last_Modified_Date__c.getDescribe(),
                            Org_Component__c.Name__c.getDescribe(),
                            Org_Component__c.Component_Type__c.getDescribe(),
                            Org_Component__c.Label__c.getDescribe(),
                            Org_Component__c.Async_Job_Id__c.getDescribe()
                        }
                    }
                );

                for (Org_Component__c orgComponent : [
                    SELECT
                        Id,
                        Attachment_ID__c,
                        Last_Updated_By__c,
                        Last_Modified_Date__c,
                        Name__c,
                        Component_Type__c,
                        Label__c,
                        Async_Job_Id__c
                    FROM Org_Component__c
                    WHERE OrganisationName__c = :organizationId AND Status__c = 'In Progress' AND Async_Job_Id__c != ''
                ]) {
                    orgComponentWrapperList.add(new OrgComponentWrapper(orgComponent));
                }
                return JSON.serialize(orgComponentWrapperList);
            }
        } else {
            throw new FlosumException('Tracking Setting not found.');
        }
        return 'false';
    }

    //deprecated
    @AuraEnabled
    public static String getLog(Map<String, Object> dataMap) {
        String metadataLogId = (String) dataMap.get('metadataLogId');

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Metadata_Log__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Status__c.getDescribe(),
                    Metadata_Log__c.Metadata_Types__c.getDescribe(),
                    Metadata_Log__c.Job_Completed__c.getDescribe(),
                    Metadata_Log__c.Completed_Date__c.getDescribe(),
                    Metadata_Log__c.Start_Date__c.getDescribe(),
                    Metadata_Log__c.Error_Log__c.getDescribe()
                }
            }
        );

        Map<Id, Metadata_Log__c> metadataLogMap = new Map<Id, Metadata_Log__c>(
            [
                SELECT Id, Status__c, Job_Completed__c, Completed_Date__c, Start_Date__c, Error_Log__c
                FROM Metadata_Log__c
                WHERE Id = :metadataLogId
                LIMIT 1
            ]
        );
        if (!metadataLogMap.isEmpty()) {
            return JSON.serialize(createLogWrappers(metadataLogMap));
        } else {
            throw new FlosumException('Metadata log by id not found.');
        }
    }

    @AuraEnabled
    public static String getLogs(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        Integer countLeft = Integer.valueOf(dataMap.get('countLeft'));
        List<String> logIdAlreadyRetrievedList = (List<String>) JSON.deserialize(
            (String) dataMap.get('logIdAlreadyRetrievedList'),
            List<String>.class
        );

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Metadata_Types__c.getDescribe(),
                    Tracking_Setting__c.Is_Enabled__c.getDescribe()
                }
            }
        );
        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Id
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];

        if (!trackingOrganizationSettingList.isEmpty()) {
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Metadata_Log__c.Status__c.getDescribe(),
                        Metadata_Log__c.Metadata_Types__c.getDescribe(),
                        Metadata_Log__c.Job_Completed__c.getDescribe(),
                        Metadata_Log__c.Completed_Date__c.getDescribe(),
                        Metadata_Log__c.Start_Date__c.getDescribe(),
                        Metadata_Log__c.Error_Log__c.getDescribe()
                    }
                }
            );

            List<TrackingService.LogWrapper> logWrapperList = new List<TrackingService.LogWrapper>();
            for (Metadata_Log__c metadataLog : [
                SELECT Id, Status__c, Job_Completed__c, Completed_Date__c, Start_Date__c, Error_Log__c
                FROM Metadata_Log__c
                WHERE
                    Tracking_Setting__c = :trackingOrganizationSettingList.get(0).Id
                    AND Id NOT IN :logIdAlreadyRetrievedList
                ORDER BY CreatedDate DESC
                LIMIT :countLeft
            ]) {
                String id = metadataLog.Id;
                String status = metadataLog.Status__c;
                Boolean isCompleted = metadataLog.Job_Completed__c;
                String errorMessage = metadataLog.Error_Log__c;
                Datetime completedDate = metadataLog.Completed_Date__c;
                Datetime startedDate = metadataLog.Start_Date__c;

                logWrapperList.add(
                    new TrackingService.LogWrapper(id, status, isCompleted, startedDate, completedDate, errorMessage)
                );
            }

            return JSON.serialize(logWrapperList);
        } else {
            throw new FlosumException('Tracking Setting by organization id not found.');
        }
    }

    public static List<TrackingService.LogWrapper> createLogWrappers(Map<Id, Metadata_Log__c> metadataLogMap) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Attachment.Body.getDescribe(),
                    Attachment.ParentId.getDescribe()
                }
            }
        );

        Map<Id, TrackingService.LogWrapper> metadataLogIdToLogWrapperListMap = new Map<Id, TrackingService.LogWrapper>();

        Integer size = 0;
        for (Attachment attach : [
            SELECT Body, BodyLength, ParentId
            FROM Attachment
            WHERE ParentId IN :metadataLogMap.keySet()
            ORDER BY CreatedDate DESC
        ]) {
            size += attach.BodyLength;
            if ((size) < 2200000) {
                String body = attach.Body.toString();
                if (!metadataLogIdToLogWrapperListMap.containsKey(attach.ParentId)) {
                    String id = metadataLogMap.get(attach.ParentId).Id;
                    String status = metadataLogMap.get(attach.ParentId).Status__c;
                    Boolean isCompleted = metadataLogMap.get(attach.ParentId).Job_Completed__c;
                    String errorMessage = metadataLogMap.get(attach.ParentId).Error_Log__c;
                    Datetime completedDate = metadataLogMap.get(attach.ParentId).Completed_Date__c;
                    Datetime startedDate = metadataLogMap.get(attach.ParentId).Start_Date__c;

                    metadataLogIdToLogWrapperListMap.put(
                        attach.ParentId,
                        new TrackingService.LogWrapper(
                            id,
                            status,
                            body,
                            isCompleted,
                            startedDate,
                            completedDate,
                            errorMessage
                        )
                    );
                } else {
                    metadataLogIdToLogWrapperListMap.get(attach.ParentId).body += body;
                }
            } else {
                return metadataLogIdToLogWrapperListMap.values();
            }
        }
        return metadataLogIdToLogWrapperListMap.values();
    }

    @AuraEnabled
    public static Map<String, Object> getLogAttachmentBody(Map<String, Object> dataMap) {
        List<String> logIdList = (List<String>) JSON.deserialize((String) dataMap.get('logIdList'), List<String>.class);
        List<String> processedAttachmentIdList = (List<String>) JSON.deserialize(
            (String) dataMap.get('processedAttachmentIdList'),
            List<String>.class
        );

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Attachment.Body.getDescribe(),
                    Attachment.ParentId.getDescribe()
                }
            }
        );

        Map<String, String> metadataLogIdToBodiesMap = new Map<String, String>();
        List<String> newProcessedAttachmentIdList = new List<String>();
        Integer size = 0;
        for (Attachment attachment : [
            SELECT BodyLength, ParentId, Body
            FROM Attachment
            WHERE ParentId IN :logIdList AND BodyLength < 2150000 AND Id NOT IN :processedAttachmentIdList
            ORDER BY CreatedDate DESC
        ]) {
            size += attachment.BodyLength;
            if ((size) < 2200000) {
                if (!metadataLogIdToBodiesMap.containsKey(attachment.ParentId)) {
                    metadataLogIdToBodiesMap.put(attachment.ParentId, attachment.Body.toString());
                } else {
                    String oldBody = metadataLogIdToBodiesMap.get(attachment.ParentId);
                    metadataLogIdToBodiesMap.put(attachment.ParentId, oldBody + attachment.Body.toString());
                }
                newProcessedAttachmentIdList.add(attachment.Id);
            } else {
                return new Map<String, Object>{
                    'metadataLogIdToBodiesMap' => metadataLogIdToBodiesMap,
                    'processedAttachmentIdList' => newProcessedAttachmentIdList
                };
            }
        }
        return new Map<String, Object>{ 'metadataLogIdToBodiesMap' => metadataLogIdToBodiesMap };
    }

    @AuraEnabled
    public static String saveSettings(Map<String, Object> dataMap) {
        String settings = (String) dataMap.get('settings');
        String organizationId = (String) dataMap.get('organizationId');
        TrackingService.TrackingOrganizationWrapper trackingOrganizationWrapper = (TrackingService.TrackingOrganizationWrapper) JSON.deserialize(
            settings,
            TrackingService.TrackingOrganizationWrapper.class
        );

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Metadata_Types__c.getDescribe(),
                    Tracking_Setting__c.Is_Enabled__c.getDescribe(),
                    Tracking_Setting__c.Current_Jobs__c.getDescribe(),
                    Tracking_Setting__c.Is_Processed__c.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Metadata_Types__c, Is_Enabled__c, Current_Jobs__c, Is_Processed__c, Organization__c
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];

        Tracking_Setting__c trackingOrganizationSetting;

        if (trackingOrganizationSettingList.isEmpty()) {
            trackingOrganizationSetting = new Tracking_Setting__c();
            trackingOrganizationSetting.Organization__c = organizationId;
        } else {
            trackingOrganizationSetting = trackingOrganizationSettingList.get(0);
        }

        String metadataTypes = String.join(trackingOrganizationWrapper.metadataTypeList, ',');

        Boolean isMetadataTypesChanged = !metadataTypes.equals(trackingOrganizationSetting.Metadata_Types__c);

        trackingOrganizationSetting.Is_Enabled__c = trackingOrganizationWrapper.isEnabled;
        trackingOrganizationSetting.Metadata_Types__c = metadataTypes;

        if (String.isBlank(metadataTypes)) {
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Metadata_Log__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
                }
            );
            List<Metadata_Log__c> metadataLogList = [
                SELECT Id
                FROM Metadata_Log__c
                WHERE Tracking_Setting__c = :trackingOrganizationSetting.Id AND Status__c = 'In Progress'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            TrackingService.Logger logger;
            if (!metadataLogList.isEmpty()) {
                logger = new TrackingService.Logger(
                    metadataLogList.get(0).Id,
                    TrackingService.TRACKING_ORGANIZATION_LOG_NAME
                );
                TrackingService.handleErrorLog(logger, 'Stopped manually.');
            }

            trackingOrganizationSetting.Is_Processed__c = false;
            trackingOrganizationSetting.Current_Jobs__c = '';

            DatabaseUtils.updateRecord(
                trackingOrganizationSetting,
                new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Current_Jobs__c.getDescribe()
                }
            );
        }

        DatabaseUtils.upsertRecord(
            trackingOrganizationSetting,
            new List<Schema.DescribeFieldResult>{
                Tracking_Setting__c.Is_Enabled__c.getDescribe(),
                Tracking_Setting__c.Metadata_Types__c.getDescribe(),
                Tracking_Setting__c.Organization__c.getDescribe()
            }
        );

        if (String.isNotBlank(metadataTypes) && (isMetadataTypesChanged)) {
            launchRetrieve();
        }

        return JSON.serialize(new TrackingService.TrackingOrganizationWrapper(trackingOrganizationSetting));
    }

    @AuraEnabled
    public static void abortStuckJobs() {
        List<AsyncApexJob> processingJobs = [
            SELECT Id, Status, CreatedDate
            FROM AsyncApexJob
            WHERE
                Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
                AND ApexClass.Name = 'TrackingAutomationScheduler'
        ];

        List<String> stackScheduleJobIdList = new List<String>();
        for (AsyncApexJob asyncApexJob : processingJobs) {
            Datetime currentDate = Datetime.now();
            Long differenceMilliseconds = currentDate.getTime() - asyncApexJob.CreatedDate.getTime();
            Long differenceSeconds = differenceMilliseconds / 1000;
            Long differenceMinutes = differenceSeconds / 60;
            Long differenceHours = differenceMinutes / 60;
            if (differenceHours > 12) {
                stackScheduleJobIdList.add(asyncApexJob.Id);
            }
        }

        if (stackScheduleJobIdList.isEmpty()) {
            return;
        }

        String domainUrl = Url.getOrgDomainUrl().toExternalForm();
        String accessToken = UserInfo.getSessionId();
        Integer count = 0;

        for (String apexJobId : stackScheduleJobIdList) {
            if (count > 30) {
                break;
            }
            String endpoint =
                domainUrl +
                '/services/data/v32.0/tooling/executeAnonymous/?anonymousBody=System.abortJob(\'' +
                apexJobId +
                '\');';
            TrackingService.callRequest(accessToken, endpoint);
        }
    }

    @AuraEnabled
    public static void handleSupportJobs() {
        TrackingAutomationScheduler.deleteSettingWithoutOrg();
        TrackingService.findStackTrackingSetting();
        TrackingAutomationScheduler.abortOldSchedulers();
    }

    @AuraEnabled
    public static void launchRetrieve() {
        List<CronTrigger> scheduledJobs = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name = :TrackingService.TRACKING_SCHEDULER_NAME
        ];
        List<AsyncApexJob> processingJobs = [
            SELECT Id, Status, CreatedDate
            FROM AsyncApexJob
            WHERE
                Status IN ('Holding', 'Queued', 'Preparing', 'Processing')
                AND ApexClass.Name = 'TrackingAutomationScheduler'
            LIMIT 1
        ];

        if (scheduledJobs.isEmpty() && processingJobs.isEmpty() && !Test.isRunningTest()) {
            Boolean isLaunch = [SELECT COUNT() FROM Tracking_Setting__c WHERE Is_Enabled__c = TRUE] > 0;

            if (isLaunch) {
                TrackingAutomationScheduler.schedule();
            }
        } else {
            if (isFirst != null && isFirst) {
                isFirst = false;
                launchRetrieve();
            }
        }
    }

    @AuraEnabled
    public static String launchManualRetrieve(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        List<String> componentIdList = (List<String>) JSON.deserialize(
            (String) dataMap.get('componentIdList'),
            List<String>.class
        );

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Last_Start_Retrieval__c.getDescribe(),
                    Tracking_Setting__c.Organization__c.getDescribe()
                }
            }
        );
        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Is_Processed__c, Last_Start_Retrieval__c, Organization__c
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];

        if (!trackingOrganizationSettingList.isEmpty()) {
            Tracking_Setting__c trackingSetting = trackingOrganizationSettingList.get(0);
            if (!trackingSetting.Is_Processed__c) {
                if (TrackingService.getIsStorageLimitExceeded())
                    throw new FlosumException(TrackingService.STORAGE_LIMIT_EXCEEDED);

                Metadata_Log__c metadataLog = TrackingService.createLog(
                    trackingSetting.Organization__c,
                    trackingSetting.Id,
                    TrackingService.PROCESS_TYPE_RETRIEVE_ORGANIZATION,
                    TrackingService.TRACKING_ORGANIZATION_LOG_NAME
                );

                TrackingService.Logger logger = new TrackingService.Logger(
                    metadataLog.Id,
                    TrackingService.TRACKING_ORGANIZATION_LOG_NAME
                );

                trackingSetting.Is_Processed__c = true;
                trackingSetting.Last_Start_Retrieval__c = Datetime.now();
                DatabaseUtils.upsertRecord(
                    trackingSetting,
                    new List<Schema.DescribeFieldResult>{
                        Tracking_Setting__c.Is_Processed__c.getDescribe(),
                        Tracking_Setting__c.Last_Start_Retrieval__c.getDescribe()
                    }
                );
                Database.executeBatch(
                    new TrackingRequestRetrieveBatch(trackingSetting.Id, logger, componentIdList, true),
                    1
                );
                return 'true';
            } else {
                return 'false';
            }
        } else {
            throw new FlosumException('Tracking Setting by organization id not found.');
        }
    }

    @AuraEnabled
    public static String createLog(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Id, Name, Is_Processed__c, Organization__r.Name
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];

        if (!trackingOrganizationSettingList.isEmpty()) {
            Metadata_Log__c metadataLog = TrackingService.createLog(
                organizationId,
                trackingOrganizationSettingList.get(0).Id,
                TrackingService.PROCESS_TYPE_RETRIEVE_ORGANIZATION,
                TrackingService.TRACKING_ORGANIZATION_LOG_NAME
            );
            List<Attachment> attachmentList = [
                SELECT Body, ParentId
                FROM Attachment
                WHERE ParentId = :metadataLog.Id
                ORDER BY CreatedDate DESC
            ];
            return JSON.serialize(
                new TrackingService.LogWrapper(
                    metadataLog.Id,
                    metadataLog.Status__c,
                    attachmentList.get(0).Body.toString(),
                    false,
                    metadataLog.Start_Date__c,
                    null,
                    ''
                )
            );
        } else {
            throw new FlosumException('Tracking Setting by organization id not found.');
        }
    }

    @AuraEnabled
    public static String updateLog(Map<String, Object> dataMap) {
        String parentId = (String) dataMap.get('parentId');
        List<String> logFile = (List<String>) JSON.deserialize((String) dataMap.get('logFile'), List<String>.class);
        TrackingService.Logger logger = new TrackingService.Logger(
            parentId,
            TrackingService.TRACKING_ORGANIZATION_LOG_NAME
        );
        logger.logFile = logFile;
        logger.updateLog();
        return 'true';
    }

    @AuraEnabled
    public static String updateTooLargeComponents(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        List<Attachment> attachmentForUpdateList = new List<Attachment>();

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Org_Component__c.Component_Type__c.getDescribe(),
                    Org_Component__c.Name__c.getDescribe(),
                    Org_Component__c.Label__c.getDescribe(),
                    Org_Component__c.Last_Updated_By__c.getDescribe(),
                    Org_Component__c.Last_Modified_Date__c.getDescribe(),
                    Org_Component__c.New_Revision_Counter__c.getDescribe(),
                    Org_Component__c.Attachment_ID__c.getDescribe(),
                    Org_Component__c.Async_Job_Id__c.getDescribe()
                }
            }
        );

        List<Org_Component__c> orgComponentList = [
            SELECT
                Id,
                Component_Type__c,
                Name__c,
                Label__c,
                Last_Updated_By__c,
                Last_Modified_Date__c,
                New_Revision_Counter__c,
                Attachment_ID__c,
                Async_Job_Id__c
            FROM Org_Component__c
            WHERE
                Is_Processed__c = TRUE
                AND Status__c = 'In Progress'
                AND Component_Type__c = 'Profile'
                AND OrganisationName__c = :organizationId
        ];

        Map<String, Org_Component__c> asyncJobOrgComponentMap = new Map<String, Org_Component__c>();
        for (Org_Component__c orgComponent : orgComponentList) {
            asyncJobOrgComponentMap.put(orgComponent.Async_Job_Id__c, orgComponent);
        }

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Attachment.Id.getDescribe(),
                    Attachment.Name.getDescribe()
                }
            }
        );

        List<Attachment> attachmentList = [
            SELECT Id, Name
            FROM Attachment
            WHERE Name IN :asyncJobOrgComponentMap.keySet()
        ];

        Map<String, Attachment> nameAttachmentMap = new Map<String, Attachment>();
        for (Attachment oneAttachment : attachmentList) {
            nameAttachmentMap.put(oneAttachment.Name, oneAttachment);
        }

        for (Org_Component__c orgComponent : orgComponentList) {
            if (nameAttachmentMap.containsKey(orgComponent.Async_Job_Id__c)) {
                Attachment largeAttachment = nameAttachmentMap.get(orgComponent.Async_Job_Id__c);
                orgComponent.Is_Retrieved__c = true;
                orgComponent.Status__c = 'Retrieved';
                orgComponent.Attachment_ID__c = largeAttachment.Id;

                largeAttachment.Name = orgComponent.Name__c;
                attachmentForUpdateList.add(largeAttachment);
            } else {
                orgComponent.Status__c = 'Too Large';
            }

            orgComponent.Is_Processed__c = false;
            orgComponent.Async_Job_Id__c = null;

            if (orgComponent.New_Revision_Counter__c != null) {
                orgComponent.Revision_Counter__c = orgComponent.New_Revision_Counter__c;
                orgComponent.New_Revision_Counter__c = null;
            }
        }

        if (!orgComponentList.isEmpty()) {
            DatabaseUtils.updateRecords(
                orgComponentList,
                new List<Schema.DescribeFieldResult>{
                    Org_Component__c.Is_Retrieved__c.getDescribe(),
                    Org_Component__c.Status__c.getDescribe(),
                    Org_Component__c.Attachment_ID__c.getDescribe(),
                    Org_Component__c.Is_Processed__c.getDescribe(),
                    Org_Component__c.Async_Job_Id__c.getDescribe(),
                    Org_Component__c.Revision_Counter__c.getDescribe(),
                    Org_Component__c.New_Revision_Counter__c.getDescribe()
                }
            );
        }

        if (!attachmentForUpdateList.isEmpty()) {
            DatabaseUtils.upsertRecords(
                attachmentForUpdateList,
                new List<Schema.DescribeFieldResult>{ Attachment.Name.getDescribe() }
            );
        }

        return 'true';
    }

    @AuraEnabled
    public static String trackingSettingAbortJob(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Id.getDescribe(),
                    Tracking_Setting__c.Current_Apex_Job_Id__c.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Id, Current_Apex_Job_Id__c
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];

        if (!trackingOrganizationSettingList.isEmpty()) {
            Tracking_Setting__c trackingSetting = trackingOrganizationSettingList.get(0);
            if (String.isNotBlank(trackingSetting.Current_Apex_Job_Id__c)) {
                if (!Test.isRunningTest())
                    System.abortJob(trackingSetting.Current_Apex_Job_Id__c);
                trackingOrganizationSettingList.get(0).Current_Apex_Job_Id__c = '';
                DatabaseUtils.upsertRecord(
                    trackingOrganizationSettingList.get(0),
                    new List<Schema.DescribeFieldResult>{ Tracking_Setting__c.Current_Apex_Job_Id__c.getDescribe() }
                );
            }
        }

        return 'true';
    }

    @AuraEnabled
    public static String finishManualRetrieve(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        String metadataLogId = (String) dataMap.get('metadataLogId');
        String finishMessage = (String) dataMap.get('finishMessage');
        TrackingService.Logger logger = new TrackingService.Logger(
            metadataLogId,
            TrackingService.TRACKING_ORGANIZATION_LOG_NAME
        );

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Id.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Id, Current_Apex_Job_Id__c
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];
        if (!trackingOrganizationSettingList.isEmpty()) {
            Tracking_Setting__c trackingSetting = trackingOrganizationSettingList.get(0);
            if (String.isNotBlank(trackingSetting.Current_Apex_Job_Id__c)) {
                if (!Test.isRunningTest())
                    System.abortJob(trackingSetting.Current_Apex_Job_Id__c);
                trackingOrganizationSettingList.get(0).Current_Apex_Job_Id__c = '';
                DatabaseUtils.upsertRecord(
                    trackingOrganizationSettingList.get(0),
                    new List<Schema.DescribeFieldResult>{ Tracking_Setting__c.Current_Apex_Job_Id__c.getDescribe() }
                );
            }
            TrackingService.handleSuccessSettings(trackingSetting.Id);
            TrackingService.handleNotProcessedOrgComponents(trackingSetting.Id, logger);
            TrackingService.handleSuccessLog(logger, finishMessage);
        }

        return 'true';
    }

    @AuraEnabled
    public static String getLogBody(Map<String, Object> dataMap) {
        String metadataLogId = (String) dataMap.get('metadataLogId');
        List<Attachment> attachmentList = [
            SELECT Body, ParentId
            FROM Attachment
            WHERE ParentId = :metadataLogId
            ORDER BY CreatedDate DESC
        ];
        if (!attachmentList.isEmpty()) {
            return attachmentList.get(0).Body.toString();
        } else {
            throw new FlosumException('Attachment not found.');
        }
    }

    @AuraEnabled
    public static String checkProcessState(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Organization__c.getDescribe(),
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Name.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Is_Processed__c
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];

        if (!trackingOrganizationSettingList.isEmpty()) {
            Tracking_Setting__c trackingSetting = trackingOrganizationSettingList.get(0);
            if (!trackingSetting.Is_Processed__c) {
                return 'Success';
            } else {
                throw new FlosumException('The process is already running, please wait for the process to complete.');
            }
        } else {
            throw new FlosumException('Tracking Setting by organization id not found.');
        }
    }

    //deprecated
    @AuraEnabled
    public static String pullChanges(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        String metadataLogId = (String) dataMap.get('metadataLogId');
        String componentListJson = (String) dataMap.get('componentList');
        Boolean isFirst = (Boolean) dataMap.get('isFirst');
        Boolean isLast = (Boolean) dataMap.get('isLast');

        Map<String, Object> resultMap = new Map<String, Object>();
        TrackingService.Logger logger = new TrackingService.Logger(
            metadataLogId,
            TrackingService.TRACKING_ORGANIZATION_LOG_NAME
        );

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Organization__c.getDescribe(),
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Name.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Id, Name, Is_Processed__c, Organization__c, Organization__r.Name, Current_Jobs__c
            FROM Tracking_Setting__c
            WHERE Organization__c = :organizationId
        ];

        if (!trackingOrganizationSettingList.isEmpty()) {
            Tracking_Setting__c trackingSetting = trackingOrganizationSettingList.get(0);

            if (isFirst) {
                if (trackingSetting.Is_Processed__c) {
                    TrackingService.handleError(
                        trackingSetting.Id,
                        logger,
                        'The process is already running, please wait for the process to complete.'
                    );
                    resultMap.put('isSuccess', false);
                    resultMap.put(
                        'errorMessage',
                        'The process is already running, please wait for the process to complete.'
                    );
                    return JSON.serialize(resultMap);
                }
            }

            try {
                if (isLast) {
                    if (!trackingSetting.Is_Processed__c && logger != null && !Test.isRunningTest()) {
                        trackingSetting.Is_Processed__c = true;
                        trackingSetting.Last_Start_Retrieval__c = Datetime.now();
                        DatabaseUtils.upsertRecord(
                            trackingSetting,
                            new List<Schema.DescribeFieldResult>{
                                Tracking_Setting__c.Is_Processed__c.getDescribe(),
                                Tracking_Setting__c.Last_Start_Retrieval__c.getDescribe()
                            }
                        );
                        Database.executeBatch(new TrackingRequestRetrieveBatch(trackingSetting.Id, logger), 1);
                    }
                }

                resultMap.put('isSuccess', true);
            } catch (Exception e) {
                TrackingService.handleError(trackingSetting.Id, logger, 'Error Start Retrieve. ' + e.getMessage());
                resultMap.put('isSuccess', false);
                resultMap.put('errorMessage', e.getMessage());
            }
        } else {
            TrackingService.handleErrorLog(logger, 'Tracking Setting by organization id not found.');
            resultMap.put('isSuccess', false);
            resultMap.put('errorMessage', 'Tracking Setting by organization id not found.');
        }
        return JSON.serialize(resultMap);
    }

    // Commit to Branch methods
    @AuraEnabled
    public static String getCommitToBranchOptions(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Repository__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Repository__c.Name.getDescribe()
                }
            }
        );

        String organizationName = '';
        List<Organisation__c> organisationList = [SELECT Name FROM Organisation__c WHERE Id = :organizationId];
        if (!organisationList.isEmpty()) {
            organizationName = organisationList.get(0).Name;
        }

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Repository__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Repository__c.Name.getDescribe()
                }
            }
        );

        List<Map<String, Object>> repositoryOptionList = new List<Map<String, Object>>();

        for (Repository__c repository : [
            SELECT Id, Name
            FROM Repository__c
            WHERE Repository_Type__c != :VeevaConstants.VEEVA_TYPE
            ORDER BY Name
            LIMIT 999
        ]) {
            repositoryOptionList.add(new Map<String, Object>{ 'value' => repository.Id, 'label' => repository.Name });
        }

        return JSON.serialize(
            new Map<String, Object>{
                'repositoryOptionList' => repositoryOptionList,
                'organizationName' => organizationName
            }
        );
    }

    @AuraEnabled
    public static String checkCommitPermissions(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        String repositoryId = (String) dataMap.get('repositoryId');
        String branchName = (String) dataMap.get('branchName');
        String branchId = (String) dataMap.get('branchId');

        if (String.isBlank(organizationId)) {
            throw new FlosumException('Organization id not provided.');
        }

        if (String.isBlank(repositoryId)) {
            throw new FlosumException('Repository id not provided.');
        }

        if (String.isBlank(branchId) && String.isBlank(branchName)) {
            throw new FlosumException('Please select existing branch or input name for new branch.');
        }

        if (!MetadataUtils.chekRepositoryPermission(repositoryId)) {
            throw new FlosumException(FlosumConstants.COMMIT_PERMISSION_DENIED);
        }

        Branch__c selectedBranch;

        if (String.isNotBlank(branchId)) {
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Branch__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Branch__c.Branch_Name__c.getDescribe(),
                        Branch__c.Repository__c.getDescribe()
                    },
                    Repository__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Repository__c.Name.getDescribe()
                    }
                }
            );

            List<Branch__c> branchList = [
                SELECT Id, Branch_Name__c, Repository__c, Repository__r.Name
                FROM Branch__c
                WHERE Id = :branchId
                LIMIT 1
            ];

            if (!branchList.isEmpty()) {
                selectedBranch = branchList.get(0);
            } else {
                throw new FlosumException('Selected branch not found.');
            }
        } else {
            selectedBranch = new Branch__c();
            selectedBranch.Repository__c = repositoryId;
            selectedBranch.Branch_Name__c = branchName;

            DatabaseUtils.insertRecord(
                selectedBranch,
                new List<Schema.DescribeFieldResult>{
                    Branch__c.Branch_Name__c.getDescribe(),
                    Branch__c.Repository__c.getDescribe()
                }
            );

            branchId = selectedBranch.Id;
        }
        RepoRestrictionController.RestrictionDetails restrictionD = RepoRestrictionController.checkForCommitRestrictions(
            organizationId,
            branchId
        );
        if (!restrictionD.isSuccess) {
            throw new FlosumException(restrictionD.errorMessage);
        }
        BranchPermissionController.MoveForwardPermission checkResult = BranchPermissionController.allowUserToMoveForwardFromBranch(
            branchId,
            BranchPermissionController.Commit_To_Branch
        );

        if (!checkResult.isSuccess) {
            throw new FlosumException(checkResult.errorMessage);
        }

        return branchId;
    }

    @AuraEnabled
    public static Map<String, Object> getBranchPipelineInfo(Map<String, Object> dataMap) {
        String branchId = (String) dataMap.get('branchId');

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Branch__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Branch__c.Pipeline__c.getDescribe()
                },
                Pipeline__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Pipeline__c.Manual__c.getDescribe(),
                    Pipeline__c.Full_Deploy__c.getDescribe(),
                    Pipeline__c.Build_and_Deploy_Organizations__c.getDescribe()
                },
                PipelineStep__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    PipelineStep__c.Pipeline__c.getDescribe()
                }
            }
        );

        List<Branch__c> branchList = [
            SELECT Id, Pipeline__c, Pipeline__r.Manual__c, Pipeline__r.Full_Deploy__c
            FROM Branch__c
            WHERE Id = :branchId AND Pipeline__c != NULL AND Pipeline__r.Manual__c = FALSE
            LIMIT 1
        ];

        if (branchList.isEmpty()) {
            return null;
        }

        Id pipelineId = branchList[0].Pipeline__c;

        List<Pipeline__c> branchPipelineList = [
            SELECT Id, Build_and_Deploy_Organizations__c, Full_Deploy__c, Manual__c
            FROM Pipeline__c
            WHERE Id = :pipelineId
            LIMIT 1
        ];

        if (branchPipelineList.isEmpty()) {
            return null;
        }

        List<PipelineStep__c> pipelineStepsList = [
            SELECT Id
            FROM PipelineStep__c
            WHERE Pipeline__c = :pipelineId
            LIMIT 1
        ];

        if (
            pipelineStepsList.isEmpty() &&
            (branchPipelineList[0].Build_and_Deploy_Organizations__c == null ||
            branchPipelineList[0].Build_and_Deploy_Organizations__c == '{}')
        ) {
            return null;
        }

        Map<String, Object> pipelineOptionMap = new Map<String, Object>();

        pipelineOptionMap.put('Id', pipelineId);
        pipelineOptionMap.put('isFullDeploy', branchList[0].Pipeline__r.Full_Deploy__c);
        pipelineOptionMap.put('pipelinePageUrl', Page.RunPipeline.getUrl());

        return pipelineOptionMap;
    }

    @AuraEnabled
    public static String insertMergeSetAttachment(Map<String, Object> dataMap) {
        String mergeSetName = 'MERGEBRANCHSET' + Datetime.now().getTime();
        String branchId = (String) dataMap.get('branchId');
        List<String> idsList = (List<String>) JSON.deserialize((String) dataMap.get('idsList'), List<String>.class);

        Attachment att = new Attachment(
            Body = Blob.valueOf(JSON.serialize(idsList)),
            ParentId = branchId,
            Description = 'MERGEBRANCHSET',
            Name = mergeSetName,
            ContentType = 'text/plain'
        );

        DatabaseUtils.insertRecord(
            att,
            new List<Schema.DescribeFieldResult>{
                Attachment.Body.getDescribe(),
                Attachment.Name.getDescribe(),
                Attachment.Description.getDescribe(),
                Attachment.ContentType.getDescribe(),
                Attachment.ParentId.getDescribe()
            }
        );

        return mergeSetName;
    }

    @AuraEnabled
    public static String getOrgComponentsInfo(Map<String, Object> dataMap) {
        String orgComponentIdListJson = (String) dataMap.get('orgComponentIdListJson');

        List<OrgComponentWrapper> orgComponentWrapperList = new List<OrgComponentWrapper>();

        List<String> orgComponentIdList = (List<String>) JSON.deserialize(orgComponentIdListJson, List<String>.class);
        if (!orgComponentIdList.isEmpty()) {
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Org_Component__c.Name.getDescribe(),
                        Org_Component__c.Attachment_ID__c.getDescribe(),
                        Org_Component__c.Last_Updated_By__c.getDescribe(),
                        Org_Component__c.Last_Modified_Date__c.getDescribe(),
                        Org_Component__c.Name__c.getDescribe(),
                        Org_Component__c.Component_Type__c.getDescribe(),
                        Org_Component__c.Label__c.getDescribe(),
                        Org_Component__c.Async_Job_Id__c.getDescribe()
                    }
                }
            );

            for (Org_Component__c orgComponent : [
                SELECT
                    Id,
                    Attachment_ID__c,
                    Last_Updated_By__c,
                    Last_Modified_Date__c,
                    Name__c,
                    Component_Type__c,
                    Label__c,
                    Async_Job_Id__c
                FROM Org_Component__c
                WHERE Id IN :orgComponentIdList
            ]) {
                orgComponentWrapperList.add(new OrgComponentWrapper(orgComponent));
            }
        }

        return JSON.serialize(orgComponentWrapperList);
    }

    @AuraEnabled
    public static String getAttachmentsInfo(Map<String, Object> dataMap) {
        String attachmentIdListJson = (String) dataMap.get('attachmentIdListJson');

        List<AttachmentWrapper> attachmentWrapperList = new List<AttachmentWrapper>();

        List<String> attachmentIdList = (List<String>) JSON.deserialize(attachmentIdListJson, List<String>.class);
        if (!attachmentIdList.isEmpty()) {
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Attachment.Name.getDescribe(),
                        Attachment.BodyLength.getDescribe(),
                        Attachment.Description.getDescribe(),
                        Attachment.ParentId.getDescribe()
                    }
                }
            );

            for (Attachment attachment : [
                SELECT Id, Name, BodyLength, Description, ParentId
                FROM Attachment
                WHERE Id IN :attachmentIdList
            ]) {
                AttachmentWrapper attachmentWrapper = new AttachmentWrapper(attachment);
                attachmentWrapperList.add(attachmentWrapper);
            }
        }

        return JSON.serialize(attachmentWrapperList);
    }

    @AuraEnabled
    public static List<AttachmentWrapper> getAttachmentsBody(Map<String, Object> dataMap) {
        String attachmentIdListJson = (String) dataMap.get('attachmentIdListJson');

        List<AttachmentWrapper> attachmentWrapperList = new List<AttachmentWrapper>();

        List<String> attachmentIdList = (List<String>) JSON.deserialize(attachmentIdListJson, List<String>.class);
        if (!attachmentIdList.isEmpty()) {
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Attachment.Name.getDescribe(),
                        Attachment.BodyLength.getDescribe(),
                        Attachment.Description.getDescribe(),
                        Attachment.ParentId.getDescribe()
                    }
                }
            );

            for (Attachment attachment : [SELECT Id, Description, Body FROM Attachment WHERE Id IN :attachmentIdList]) {
                AttachmentWrapper attachmentWrapper = new AttachmentWrapper(
                    attachment.Id,
                    attachment.Description,
                    attachment.Body
                );

                if (FlosumConstants.ProfileRecordTypeSet.contains(attachmentWrapper.description)) {
                    attachmentWrapper.componentType = 'Profile';
                } else if (FlosumConstants.PermissionSetRecordTypeSet.contains(attachmentWrapper.description)) {
                    attachmentWrapper.componentType = 'PermissionSet';
                } else {
                    attachmentWrapper.componentType = attachmentWrapper.description;
                }
                attachmentWrapperList.add(attachmentWrapper);
            }
        }
        return attachmentWrapperList;
    }

    @AuraEnabled
    public static String compareOrgComponentsAndBranchComponents(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        String branchId = (String) dataMap.get('branchId');
        String orgComponentIdToCrcCodeMapJson = (String) dataMap.get('orgComponentIdToCrcCodeMapJson');
        Map<String, Object> orgComponentIdToCrcCodeMap = (Map<String, Object>) JSON.deserializeUntyped(
            orgComponentIdToCrcCodeMapJson
        );

        if (String.isBlank(organizationId)) {
            throw new FlosumException('Organization id not provided.');
        }

        if (String.isBlank(branchId)) {
            throw new FlosumException('Branch id not provided.');
        }

        if (orgComponentIdToCrcCodeMap.isEmpty()) {
            throw new FlosumException('Crc map is empty.');
        }

        Set<String> metaRecordTypeSet = new Set<String>();
        Set<String> metaFullNameSet = new Set<String>();

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Branch__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Branch__c.Branch_Name__c.getDescribe(),
                    Branch__c.Repository__c.getDescribe()
                }
            }
        );

        List<Branch__c> branchList = [
            SELECT Id, Branch_Name__c, LastModifiedById, Repository__c
            FROM Branch__c
            WHERE Id = :branchId
            LIMIT 1
        ];

        if (!branchList.isEmpty()) {
            CompareResultWrapper compareResultWrapper = new CompareResultWrapper();

            Map<String, Org_Component__c> typeNameKeyToOrgComponentMap = new Map<String, Org_Component__c>();
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Org_Component__c.CRC32__c.getDescribe(),
                        Org_Component__c.API_Name__c.getDescribe(),
                        Org_Component__c.Component_Type__c.getDescribe(),
                        Org_Component__c.Last_Updated_By__c.getDescribe(),
                        Org_Component__c.OrganisationName__c.getDescribe()
                    }
                }
            );

            for (Org_Component__c orgComponent : [
                SELECT Id, CRC32__c, API_Name__c, Component_Type__c, Last_Updated_By__c
                FROM Org_Component__c
                WHERE OrganisationName__c = :organizationId AND Id IN :orgComponentIdToCrcCodeMap.keySet()
            ]) {
                metaRecordTypeSet.add(orgComponent.Component_Type__c);
                metaFullNameSet.add(orgComponent.API_Name__c);
                orgComponent.CRC32__c = (String) orgComponentIdToCrcCodeMap.get(orgComponent.Id);

                typeNameKeyToOrgComponentMap.put(
                    getKey(orgComponent.Component_Type__c, orgComponent.API_Name__c),
                    orgComponent
                );
            }

            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Component__c.CRC32__c.getDescribe(),
                        Component__c.Component_Type__c.getDescribe(),
                        Component__c.Component_Name__c.getDescribe(),
                        Component__c.Version__c.getDescribe(),
                        Component__c.Name.getDescribe(),
                        Component__c.Last_Updated_By__c.getDescribe(),
                        Component__c.Branch__c.getDescribe(),
                        Component__c.Repository__c.getDescribe()
                    },
                    Component_History__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Component_History__c.CRC32__c.getDescribe(),
                        Component_History__c.Version__c.getDescribe()
                    }
                }
            );

            for (Component__c component : [
                SELECT
                    Id,
                    CRC32__c,
                    Component_Type__c,
                    Component_Name__c,
                    RecordType.Name,
                    Version__c,
                    Name,
                    Last_Updated_By__c,
                    (SELECT CRC32__c, Version__c FROM Components__r ORDER BY Version__c DESC LIMIT 200)
                FROM Component__c
                WHERE
                    ((RecordType.Name = 'Branch'
                    AND Branch__c = :branchId)
                    OR (RecordType.Name = 'Repository'
                    AND Repository__c = :branchList[0].Repository__c))
                    AND Component_Name__c IN :metaFullNameSet
                    AND Component_Type__c IN :metaRecordTypeSet
                ORDER BY RecordType.Name DESC
            ]) {
                String key = getKey(component.Component_Type__c, component.Component_Name__c);
                if (typeNameKeyToOrgComponentMap.containsKey(key)) {
                    // conflict or safe
                    Org_Component__c orgComponent = typeNameKeyToOrgComponentMap.get(key);
                    if (component.RecordType.Name == 'Repository') {
                        if (component.Components__r != null && component.Components__r.size() > 0) {
                            for (Component_History__c his : component.Components__r) {
                                if (orgComponent.CRC32__c == his.CRC32__c) {
                                    compareResultWrapper.notCommitList.add(
                                        new NotCommitWrapper(
                                            orgComponent.Id,
                                            his.Version__c,
                                            'The same as Version ' +
                                            his.Version__c +
                                            ' in Repository'
                                        )
                                    );
                                    typeNameKeyToOrgComponentMap.remove(key);
                                    break;
                                }
                            }
                        }
                    } else {
                        Boolean isFound = false;
                        String componentHistoryId = '0';
                        if (component.Components__r != null && component.Components__r.size() > 0) {
                            for (Component_History__c his : component.Components__r) {
                                if (orgComponent.CRC32__c == his.CRC32__c) {
                                    compareResultWrapper.notCommitList.add(
                                        new NotCommitWrapper(
                                            orgComponent.Id,
                                            his.Version__c,
                                            'The same as Version ' +
                                            his.Version__c +
                                            ' in Branch'
                                        )
                                    );
                                    isFound = true;
                                    break;
                                }
                            }
                            componentHistoryId = component.Components__r[0].Id;
                        }
                        //if component already exist in Branch with same LastModifiedDate add it to Not Commit Section.
                        if (isFound) {
                        } else if (orgComponent.Last_Updated_By__c == component.Last_Updated_By__c) {
                            compareResultWrapper.safeCommit.put(orgComponent.Id, componentHistoryId);
                        } else {
                            compareResultWrapper.conflictCommit.put(orgComponent.Id, componentHistoryId);
                        }
                        typeNameKeyToOrgComponentMap.remove(key);
                    }
                }
            }
            // add all the rest as new
            for (Org_Component__c meta : typeNameKeyToOrgComponentMap.values()) {
                compareResultWrapper.safeCommit.put(meta.Id, '0');
            }
            return JSON.serialize(compareResultWrapper);
        }
        return '';
    }

    @AuraEnabled
    public static String setBranchProcessed(Map<String, Object> dataMap) {
        String organizationId = (String) dataMap.get('organizationId');
        String branchId = (String) dataMap.get('branchId');

        if (String.isBlank(organizationId)) {
            throw new FlosumException('Organization id not provided.');
        }

        if (String.isBlank(branchId)) {
            throw new FlosumException('Branch id not provided.');
        }

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Branch__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Branch__c.Branch_Name__c.getDescribe(),
                    Branch__c.Repository__c.getDescribe(),
                    Branch__c.isConflict__c.getDescribe(),
                    Branch__c.Status__c.getDescribe(),
                    Branch__c.Last_Updated_On__c.getDescribe()
                },
                Repository__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Repository__c.Name.getDescribe()
                }
            }
        );

        List<Branch__c> branchList = [
            SELECT Id, Branch_Name__c, Repository__c, Repository__r.Name, isConflict__c, Status__c, Last_Updated_On__c
            FROM Branch__c
            WHERE Id = :branchId
            LIMIT 1
        ];

        if (!branchList.isEmpty()) {
            if (MetadataUtils.chekRepositoryPermission(branchList[0].Repository__c)) {
                branchList[0].Last_Updated_On__c = System.now();
                branchList[0].Status__c = 'In Progress';
                branchList[0].isConflict__c = false;
                DatabaseUtils.updateRecords(
                    branchList,
                    new List<Schema.DescribeFieldResult>{
                        Branch__c.Last_Updated_On__c.getDescribe(),
                        Branch__c.Status__c.getDescribe(),
                        Branch__c.isConflict__c.getDescribe()
                    }
                );
            } else {
                throw new FlosumException(FlosumConstants.COMMIT_PERMISSION_DENIED);
            }
        }
        return null;
    }

    @AuraEnabled
    public static void updateComponentsWithDependencies(String dependencyComponentJson) {
        ComponentWithDependencyWrapper dependencyComponent = (ComponentWithDependencyWrapper) JSON.deserialize(
            dependencyComponentJson,
            ComponentWithDependencyWrapper.class
        );

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Attachment.Id.getDescribe()
                }
            }
        );

        List<Attachment> attachments = [SELECT Id FROM Attachment WHERE Id = :dependencyComponent.attachmentId];

        if (attachments.isEmpty()) {
            return;
        }

        Attachment att = attachments.get(0);
        att.Body = EncodingUtil.base64Decode(dependencyComponent.body);

        DatabaseUtils.updateRecord(
            att,
            new List<Schema.DescribeFieldResult>{ Attachment.Body.getDescribe() }
        );
    }

    @AuraEnabled
    public static void prepareToCommit(String branchId) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Branch__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
            }
        );

        List<Branch__c> branchList = [SELECT Id FROM Branch__c WHERE Id = :branchId LIMIT 1];

        if (branchList.isEmpty()) {
            throw new FlosumException('Branch not found!');
        }
        branchList[0].Last_Updated_On__c = System.now();
        branchList[0].Status__c = 'In Progress';
        branchList[0].isConflict__c = false;

        DatabaseUtils.updateRecords(
            branchList,
            new List<Schema.DescribeFieldResult>{
                Branch__c.Last_Updated_On__c.getDescribe(),
                Branch__c.Status__c.getDescribe(),
                Branch__c.isConflict__c.getDescribe()
            }
        );
    }

    @AuraEnabled
    public static void completeCommit(String branchId) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Branch__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
            }
        );

        List<Branch__c> branchList = [SELECT Id FROM Branch__c WHERE Id = :branchId LIMIT 1];

        if (branchList.isEmpty()) {
            throw new FlosumException('Branch not found!');
        }
        branchList[0].Status__c = 'Completed';

        DatabaseUtils.updateRecords(
            branchList,
            new List<Schema.DescribeFieldResult>{ Branch__c.Status__c.getDescribe() }
        );
    }

    @AuraEnabled
    public static String commitToBranch(String commitToBranchWrapperJson) {
        CommitToBranchWrapper commitToBranchWrapper = (CommitToBranchWrapper) JSON.deserialize(
            commitToBranchWrapperJson,
            CommitToBranchWrapper.class
        );
        commitToBranchWrapperJson = null;

        if (String.isBlank(commitToBranchWrapper.organizationId)) {
            throw new FlosumException('Organization id not provided.');
        }

        if (String.isBlank(commitToBranchWrapper.organizationName)) {
            throw new FlosumException('organization Name not provided.');
        }

        if (String.isBlank(commitToBranchWrapper.branchId)) {
            throw new FlosumException('Branch id not provided.');
        }

        Datetime commitDateTime = Datetime.now();
        String committerName = UserInfo.getName();
        Set<String> orgComponentRecordTypeSet = new Set<String>();
        Set<String> orgComponentApiNameSet = new Set<String>();
        Set<String> committedComponentIds = new Set<String>();

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Branch__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Branch__c.Repository__c.getDescribe(),
                    Branch__c.Deployment_Mode__c.getDescribe(),
                    Branch__c.Deployment_Style__c.getDescribe()
                }
            }
        );

        List<Branch__c> branchList = [
            SELECT Id, Repository__c, LastModifiedById, Deployment_Mode__c, Deployment_Style__c
            FROM Branch__c
            WHERE Id = :commitToBranchWrapper.branchId
            LIMIT 1
        ];

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Attachment.Body.getDescribe()
                }
            }
        );

        Map<String, Attachment> attachmentMap = new Map<String, Attachment>(
            [SELECT Id, Body FROM Attachment WHERE Id IN :commitToBranchWrapper.attachmentIdList]
        );

        if (!branchList.isEmpty()) {
            String componentObjectName = Schema.SObjectType.Component__c.getName();
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    RecordType.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        RecordType.Name.getDescribe(),
                        RecordType.SobjectType.getDescribe()
                    }
                }
            );

            List<RecordType> recordTypeList = [
                SELECT Id, Name
                FROM RecordType
                WHERE SobjectType = :componentObjectName AND Name = 'Branch'
                LIMIT 1
            ];

            if (
                commitToBranchWrapper.destructiveChangeList != null &&
                !commitToBranchWrapper.destructiveChangeList.isEmpty()
            ) {
                List<Destructive_Changes__c> updateDestructiveChangeList = [
                    SELECT Id, Component_Name__c, Component_Type__c
                    FROM Destructive_Changes__c
                    WHERE Branch__c = :commitToBranchWrapper.branchId
                ];
                List<Destructive_Changes__c> insertDestructiveChangeList = new List<Destructive_Changes__c>();
                Map<String, Destructive_Changes__c> keyToDestructiveChangeMap = new Map<String, Destructive_Changes__c>();

                for (Destructive_Changes__c destructiveChanges : updateDestructiveChangeList) {
                    String key = destructiveChanges.Component_Type__c + '#' + destructiveChanges.Component_Name__c;
                    keyToDestructiveChangeMap.put(key, destructiveChanges);
                }

                for (DestructiveChangesWrapper destructiveChangeWrapper : commitToBranchWrapper.destructiveChangeList) {
                    String key = destructiveChangeWrapper.componentType + '#' + destructiveChangeWrapper.componentName;
                    Destructive_Changes__c destructiveChanges;
                    if (keyToDestructiveChangeMap.containsKey(key)) {
                        destructiveChanges = keyToDestructiveChangeMap.get(key);
                        destructiveChanges.Post_Deployment_Change__c = destructiveChangeWrapper.isPostDeploy;
                    } else {
                        destructiveChanges = new Destructive_Changes__c();
                        destructiveChanges.Component_Name__c = destructiveChangeWrapper.componentName;
                        destructiveChanges.Component_Type__c = destructiveChangeWrapper.componentType;
                        destructiveChanges.Branch__c = commitToBranchWrapper.branchId;
                        insertDestructiveChangeList.add(destructiveChanges);
                    }
                }

                DatabaseUtils.insertRecords(
                    insertDestructiveChangeList,
                    new List<Schema.DescribeFieldResult>{
                        Destructive_Changes__c.Post_Deployment_Change__c.getDescribe(),
                        Destructive_Changes__c.Component_Type__c.getDescribe(),
                        Destructive_Changes__c.Component_Name__c.getDescribe(),
                        Destructive_Changes__c.Branch__c.getDescribe()
                    }
                );

                DatabaseUtils.updateRecords(
                    updateDestructiveChangeList,
                    new List<Schema.DescribeFieldResult>{
                        Destructive_Changes__c.Post_Deployment_Change__c.getDescribe()
                    }
                );
            }

            if (!recordTypeList.isEmpty()) {
                List<Component__c> insertComponentList = new List<Component__c>();
                List<Component__c> updateComponentList = new List<Component__c>();
                List<Component_History__c> componentHistoryList = new List<Component_History__c>();
                Map<String, Component__c> committedComponentMap = new Map<String, Component__c>();
                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            Org_Component__c.API_Name__c.getDescribe(),
                            Org_Component__c.Label__c.getDescribe(),
                            Org_Component__c.Component_Type__c.getDescribe(),
                            Org_Component__c.Last_Modified_Date__c.getDescribe(),
                            Org_Component__c.Last_Updated_By__c.getDescribe(),
                            Org_Component__c.OrganisationName__c.getDescribe()
                        }
                    }
                );

                for (Org_Component__c orgComponent : [
                    SELECT
                        Id,
                        API_Name__c,
                        Label__c,
                        Component_Type__c,
                        Last_Modified_Date__c,
                        LastModifiedBy.Name,
                        Last_Updated_By__c
                    FROM Org_Component__c
                    WHERE
                        OrganisationName__c = :commitToBranchWrapper.organizationId
                        AND Id IN :commitToBranchWrapper.orgComponentIdList
                ]) {
                    String key = orgComponent.Component_Type__c + '#' + orgComponent.API_Name__c;

                    Component__c component = new Component__c();
                    component.Component_Type__c = orgComponent.Component_Type__c;
                    component.Component_Name__c = orgComponent.API_Name__c;
                    component.File_Name__c = orgComponent.Label__c;
                    component.Last_Modified_Date__c = orgComponent.Last_Modified_Date__c;
                    component.Last_Updated_By__c = orgComponent.Last_Updated_By__c;
                    component.Committed_On__c = commitDateTime;
                    component.Last_Modified_By__c = committerName;
                    component.Branch__c = branchList[0].Id;
                    component.RecordTypeId = recordTypeList[0].Id;
                    component.Version__c = 1;
                    component.Org_ID__c = commitToBranchWrapper.organizationId;
                    component.Parent_ID__c = commitToBranchWrapper.organizationId;
                    component.Source__c = 'Organization';
                    component.Parent_Name__c = commitToBranchWrapper.organizationName;
                    if (commitToBranchWrapper.orgComponentIdToDataMap.containsKey(key)) {
                        component.CRC32__c = commitToBranchWrapper.orgComponentIdToDataMap.get(key).crc32;
                        orgComponentRecordTypeSet.add(orgComponent.Component_Type__c);
                        orgComponentApiNameSet.add(orgComponent.API_Name__c);
                        committedComponentMap.put(key, component);
                    }
                }
                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            Component__c.CRC32__c.getDescribe(),
                            Component__c.Component_Type__c.getDescribe(),
                            Component__c.Component_Name__c.getDescribe(),
                            Component__c.Version__c.getDescribe(),
                            Component__c.Name.getDescribe(),
                            Component__c.Last_Modified_Date__c.getDescribe(),
                            Component__c.Last_Updated_By__c.getDescribe(),
                            Component__c.Committed_On__c.getDescribe(),
                            Component__c.Last_Modified_By__c.getDescribe(),
                            Component__c.Branch__c.getDescribe()
                        }
                    }
                );
                String timestamp = '' + Datetime.now().getTime();
                for (Component__c component : [
                    SELECT
                        Id,
                        CRC32__c,
                        Component_Type__c,
                        Component_Name__c,
                        RecordType.Name,
                        Version__c,
                        Name,
                        Last_Modified_Date__c,
                        Last_Updated_By__c,
                        Committed_On__c,
                        Last_Modified_By__c
                    FROM Component__c
                    WHERE
                        Branch__c = :commitToBranchWrapper.branchId
                        AND Component_Name__c IN :orgComponentApiNameSet
                        AND Component_Type__c IN :orgComponentRecordTypeSet
                ]) {
                    String key = component.Component_Type__c + '#' + component.Component_Name__c;
                    if (committedComponentMap.containsKey(key)) {
                        Component__c updateComp = committedComponentMap.get(key);
                        //creating component componentHistory
                        Component_History__c componentHistory = new Component_History__c(
                            Component__c = component.Id,
                            Version__c = component.Version__c + 1,
                            CRC32__c = updateComp.CRC32__c,
                            Changed_By__c = updateComp.Last_Updated_By__c,
                            Changed_On__c = updateComp.Last_Modified_Date__c,
                            External_Committed_By__c = timestamp,
                            Action_Type__c = 'Commit',
                            Source_Type__c = 'Organization',
                            Source_Name__c = commitToBranchWrapper.organizationName,
                            Source_Id__c = commitToBranchWrapper.organizationId
                        );
                        componentHistoryList.add(componentHistory);

                        //updating old record
                        component.File_Name__c = updateComp.File_Name__c;
                        component.Last_Modified_Date__c = updateComp.Last_Modified_Date__c;
                        component.Last_Updated_By__c = updateComp.Last_Updated_By__c;
                        component.Committed_On__c = commitDateTime;
                        component.Last_Modified_By__c = committerName;
                        component.Version__c = component.Version__c + 1;
                        component.CRC32__c = updateComp.CRC32__c;
                        component.Comments__c = null;
                        component.Org_Id__c = commitToBranchWrapper.organizationId;
                        component.Parent_ID__c = commitToBranchWrapper.organizationId;
                        component.Source__c = 'Organization';
                        component.Parent_Name__c = commitToBranchWrapper.organizationName;
                        updateComponentList.add(component);
                        committedComponentMap.remove(key);
                        committedComponentIds.add(component.Id);
                    }
                }
                orgComponentApiNameSet.clear();
                orgComponentRecordTypeSet.clear();

                for (Component__c comp : committedComponentMap.values()) {
                    insertComponentList.add(comp);
                }
                committedComponentMap.clear();
                //upsert component and Component History records
                if (!insertComponentList.isEmpty()) {
                    DatabaseUtils.insertRecords(
                        insertComponentList,
                        new List<Schema.DescribeFieldResult>{
                            Component__c.Component_Type__c.getDescribe(),
                            Component__c.Component_Name__c.getDescribe(),
                            Component__c.File_Name__c.getDescribe(),
                            Component__c.Last_Modified_Date__c.getDescribe(),
                            Component__c.Last_Updated_By__c.getDescribe(),
                            Component__c.Committed_On__c.getDescribe(),
                            Component__c.Last_Modified_By__c.getDescribe(),
                            Component__c.Branch__c.getDescribe(),
                            Component__c.RecordTypeId.getDescribe(),
                            Component__c.CRC32__c.getDescribe(),
                            Component__c.Version__c.getDescribe(),
                            Component__c.Org_Id__c.getDescribe(),
                            Component__c.Parent_ID__c.getDescribe(),
                            Component__c.Source__c.getDescribe(),
                            Component__c.Parent_Name__c.getDescribe()
                        }
                    );
                    for (Component__c component : insertComponentList) {
                        Component_History__c history = new Component_History__c(
                            Component__c = component.Id,
                            Version__c = component.Version__c,
                            CRC32__c = component.CRC32__c,
                            Changed_By__c = component.Last_Updated_By__c,
                            Changed_On__c = component.Last_Modified_Date__c,
                            External_Committed_By__c = timestamp,
                            Action_Type__c = 'Commit',
                            Source_Type__c = component.Source__c,
                            Source_Name__c = component.Parent_Name__c,
                            Source_Id__c = component.Parent_ID__c
                        );
                        committedComponentIds.add(component.Id);
                        componentHistoryList.add(history);
                    }
                    insertComponentList.clear();
                }
                if (!updateComponentList.isEmpty()) {
                    DatabaseUtils.updateRecords(
                        updateComponentList,
                        new List<Schema.DescribeFieldResult>{
                            Component__c.File_Name__c.getDescribe(),
                            Component__c.Last_Modified_Date__c.getDescribe(),
                            Component__c.Last_Updated_By__c.getDescribe(),
                            Component__c.Committed_On__c.getDescribe(),
                            Component__c.Last_Modified_By__c.getDescribe(),
                            Component__c.Version__c.getDescribe(),
                            Component__c.CRC32__c.getDescribe(),
                            Component__c.Comments__c.getDescribe(),
                            Component__c.Org_ID__c.getDescribe(),
                            Component__c.Parent_ID__c.getDescribe(),
                            Component__c.Source__c.getDescribe(),
                            Component__c.Parent_Name__c.getDescribe()
                        }
                    );
                    updateComponentList.clear();
                }
                if (!componentHistoryList.isEmpty()) {
                    DatabaseUtils.insertRecords(
                        componentHistoryList,
                        new List<Schema.DescribeFieldResult>{
                            Component_History__c.Component__c.getDescribe(),
                            Component_History__c.Version__c.getDescribe(),
                            Component_History__c.CRC32__c.getDescribe(),
                            Component_History__c.Changed_By__c.getDescribe(),
                            Component_History__c.Changed_On__c.getDescribe(),
                            Component_History__c.External_Committed_By__c.getDescribe()
                        }
                    );
                    List<Attachment> attachmentList = new List<Attachment>();
                    List<String> componentHistoryIdList = new List<String>();
                    DatabaseUtils.checkObjectsAndFieldsAccessibility(
                        new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                            Component_History__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                                Component_History__c.Component__c.getDescribe()
                            },
                            Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                                Component__c.Component_Type__c.getDescribe(),
                                Component__c.Component_Name__c.getDescribe()
                            }
                        }
                    );

                    for (Component_History__c componentHistory : [
                        SELECT Id, Component__r.Component_Type__c, Component__r.Component_Name__c
                        FROM Component_History__c
                        WHERE Id IN :componentHistoryList
                    ]) {
                        String key =
                            componentHistory.Component__r.Component_Type__c +
                            '#' +
                            componentHistory.Component__r.Component_Name__c;

                        if (commitToBranchWrapper.orgComponentIdToDataMap.containsKey(key)) {
                            String attachmentId = commitToBranchWrapper.orgComponentIdToDataMap.get(key).attachmentId;
                            if (attachmentMap.containsKey(attachmentId)) {
                                Attachment componentAttachment = new Attachment(
                                    Name = componentHistory.Component__r.Component_Type__c,
                                    ParentId = componentHistory.Id,
                                    Description = componentHistory.Component__r.Component_Type__c,
                                    ContentType = 'application/zip'
                                );
                                componentAttachment.Body = attachmentMap.get(attachmentId).Body;
                                commitToBranchWrapper.orgComponentIdToDataMap.remove(key);
                                attachmentList.add(componentAttachment);
                            }
                        }
                        componentHistoryIdList.add(componentHistory.Id);
                    }
                    if (!attachmentList.isEmpty()) {
                        DatabaseUtils.insertRecords(
                            attachmentList,
                            new List<Schema.DescribeFieldResult>{
                                Attachment.Body.getDescribe(),
                                Attachment.Name.getDescribe(),
                                Attachment.Description.getDescribe(),
                                Attachment.ContentType.getDescribe(),
                                Attachment.ParentId.getDescribe()
                            }
                        );
                    }
                    componentHistoryList.clear();
                    attachmentList.clear();
                }
            }
        }
        return JSON.serialize(committedComponentIds);
    }

    @AuraEnabled
    public static String createBranchActivity(Map<String, Object> dataMap) {
        String type = dataMap.containsKey('type') ? (String) dataMap.get('type') : '';
        String organizationId = dataMap.containsKey('organizationId') ? (String) dataMap.get('organizationId') : '';
        String branchId = dataMap.containsKey('branchId') ? (String) dataMap.get('branchId') : '';
        List<String> idsList = new List<String>();
        switch on type {
            when 'commitToBranch' {
                idsList = (List<String>) JSON.deserialize((String) dataMap.get('idsList'), List<String>.class);
                BranchActivityController.createOrgCommitCompLog(new Set<String>(idsList), branchId, organizationId);
            }
        }
        return 'true';
    }

    @AuraEnabled
    public static void integrateWithExternalServices(Map<String, Object> dataMap) {
        // Integration with external services
        String branchId = dataMap.containsKey('branchId') ? (String) dataMap.get('branchId') : '';
        List<String> idsList = (List<String>) JSON.deserialize((String) dataMap.get('idsList'), List<String>.class);
        String timestamp = '' + DateTime.now().getTime();
        List<Branch__c> branchList = new List<Branch__c>();
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Branch__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Branch__c.Repository__c.getDescribe(),
                    Branch__c.Review_State__c.getDescribe(),
                    Branch__c.Review_Result__c.getDescribe()
                }
            }
        );
        branchList = [
            SELECT Id, Repository__c, LastModifiedById, Review_State__c, Review_Result__c
            FROM Branch__c
            WHERE Id = :branchId
            LIMIT 1
        ];
        if (branchList.size() == 1) {
            branchList[0].Timestamp__c = System.now();
            DatabaseUtils.updateRecord(
                branchList[0],
                new List<Schema.DescribeFieldResult>{ Branch__c.Timestamp__c.getDescribe() }
            );

            HerokuCredentials__c hc = HTTPService.getCredentials('REVIEW');
            if (hc != null && hc.isAutoSync__c) {
                if (hc.IsFullReview__c) {
                    Set<String> allCompIds = new Set<String>();
                    for (Component__c c : [
                        SELECT Id
                        FROM Component__c
                        WHERE Branch__c = :branchList[0].Id
                        LIMIT 49900
                    ]) {
                        allCompIds.add(c.id);
                    }
                    TaskSchedule.addReviewJob(branchList[0].Id, allCompIds);
                } else {
                    TaskSchedule.addReviewJob(branchList[0].Id, new Set<String>(idsList));
                }
                branchList[0].Review_State__c = 'QUEUED';
                branchList[0].Review_Result__c = 0;
                DatabaseUtils.updateRecord(
                    branchList[0],
                    new List<Schema.DescribeFieldResult>{
                        Branch__c.Review_State__c.getDescribe(),
                        Branch__c.Review_Result__c.getDescribe()
                    }
                );
            }

            String syncDirection = ExtSynchronize.getSyncDirection();
            if (syncDirection != '' && syncDirection.contains('SFGIT')) {
                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        RepositoryCredentials__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            RepositoryCredentials__c.RepositoryId__c.getDescribe(),
                            RepositoryCredentials__c.isLinked__c.getDescribe()
                        }
                    }
                );
                List<RepositoryCredentials__c> rCreds = [
                    SELECT Id
                    FROM RepositoryCredentials__c
                    WHERE RepositoryId__c = :branchList[0].Repository__c AND isLinked__c = TRUE
                    LIMIT 1
                ];
                if (rCreds != null && rCreds.size() == 1) {
                    TaskSchedule.addSyncJob(branchList[0].Repository__c, branchList[0].Id, timestamp);
                }
            }
            TaskSchedule.executeJobs();
        }
    }

    private static String getKey(String cType, String cName) {
        if (cName != null) {
            return cType + '#' + cName.toLowerCase();
        } else {
            return cType + '#' + cName;
        }
    }

    public class AttachmentWrapper {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Integer size;
        @AuraEnabled
        public String body;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String parentId;
        @AuraEnabled
        public String componentType;
        @AuraEnabled
        public String orgComponentId;

        public AttachmentWrapper(Attachment attachment) {
            id = attachment.Id;
            name = attachment.Name;
            size = attachment.BodyLength;
            description = attachment.Description;
            parentId = attachment.ParentId;
        }

        public AttachmentWrapper(String id, String description, Blob body) {
            this.id = id;
            this.description = description;
            this.body = EncodingUtil.base64Encode(body);
        }
    }

    public class OrgComponentWrapper {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String attachmentId;
        @AuraEnabled
        public String changedBy;
        @AuraEnabled
        public Datetime changedOn;
        @AuraEnabled
        public String componentName;
        @AuraEnabled
        public String componentType;
        @AuraEnabled
        public String fileName;
        @AuraEnabled
        public String asyncJobId;

        public OrgComponentWrapper(Org_Component__c orgComponent) {
            id = orgComponent.Id;
            attachmentId = orgComponent.Attachment_ID__c;
            changedBy = orgComponent.Last_Updated_By__c;
            changedOn = orgComponent.Last_Modified_Date__c;
            componentName = orgComponent.Name__c;
            componentType = orgComponent.Component_Type__c;
            fileName = orgComponent.Label__c;
            asyncJobId = orgComponent.Async_Job_Id__c;
        }
    }

    public class CompareResultWrapper {
        @AuraEnabled
        public List<NotCommitWrapper> notCommitList;
        @AuraEnabled
        public Map<String, String> safeCommit;
        @AuraEnabled
        public Map<String, String> conflictCommit;

        public CompareResultWrapper() {
            notCommitList = new List<NotCommitWrapper>();
            safeCommit = new Map<String, String>();
            conflictCommit = new Map<String, String>();
        }
    }

    public class NotCommitWrapper {
        public String id;
        public Decimal sameToVersion;
        public String reason;

        public NotCommitWrapper(String id, Decimal sameToVersion, String reason) {
            this.id = id;
            this.sameToVersion = sameToVersion;
            this.reason = reason;
        }
    }

    public class CommitToBranchWrapper {
        @AuraEnabled
        public List<DestructiveChangesWrapper> destructiveChangeList;
        @AuraEnabled
        public List<String> orgComponentIdList;
        @AuraEnabled
        public List<String> attachmentIdList;
        @AuraEnabled
        public String organizationId;
        @AuraEnabled
        public String organizationName;
        @AuraEnabled
        public String branchId;
        @AuraEnabled
        public Map<String, CommitToBranchComponentWrapper> orgComponentIdToDataMap;
    }

    public class CommitToBranchComponentWrapper {
        @AuraEnabled
        public String attachmentId;
        @AuraEnabled
        public String crc32;
    }

    public class ComponentWithDependencyWrapper {
        @AuraEnabled
        public String attachmentId;
        @AuraEnabled
        public String body;
    }

    public class ComponentHistoryWrapper {
        @AuraEnabled
        public String componentName;
        @AuraEnabled
        public String componentType;
        @AuraEnabled
        public String componentHistoryId;

        public ComponentHistoryWrapper(String componentName, String componentType, String componentHistoryId) {
            this.componentName = componentName;
            this.componentType = componentType;
            this.componentHistoryId = componentHistoryId;
        }
    }

    public class DestructiveChangesWrapper {
        @AuraEnabled
        public String componentName;
        @AuraEnabled
        public String componentType;
        @AuraEnabled
        public Boolean isPostDeploy;

        public DestructiveChangesWrapper(String componentName, String componentType, Boolean isPostDeploy) {
            this.componentName = componentName;
            this.componentType = componentType;
            this.isPostDeploy = isPostDeploy;
        }
    }
}