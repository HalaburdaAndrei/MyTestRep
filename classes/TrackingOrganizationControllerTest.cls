@IsTest
public with sharing class TrackingOrganizationControllerTest {
    public static final String METADATA_TYPES_DESCRIBE = '{"metadataObjects":[{"xmlName_type_info":["xmlName","http://soap.sforce.com/2006/04/metadata",null,"1","1","false"],"xmlName":"ApexClass","suffix_type_info":["suffix","http://soap.sforce.com/2006/04/metadata",null,"0","1","false"],"suffix":"installedPackage","metaFile_type_info":["metaFile","http://soap.sforce.com/2006/04/metadata",null,"1","1","false"],"metaFile":false,"inFolder_type_info":["inFolder","http://soap.sforce.com/2006/04/metadata",null,"1","1","false"],"inFolder":false,"field_order_type_info":["childXmlNames","directoryName","inFolder","metaFile","suffix","xmlName"],"directoryName_type_info":["directoryName","http://soap.sforce.com/2006/04/metadata",null,"1","1","false"],"directoryName":"installedPackages","childXmlNames_type_info":["childXmlNames","http://soap.sforce.com/2006/04/metadata",null,"0","-1","false"],"childXmlNames":null,"apex_schema_type_info":["http://soap.sforce.com/2006/04/metadata","true","false"]},{"xmlName_type_info":["xmlName","http://soap.sforce.com/2006/04/metadata",null,"1","1","false"],"xmlName":"ApexPage","suffix_type_info":["suffix","http://soap.sforce.com/2006/04/metadata",null,"0","1","false"],"suffix":"labels","metaFile_type_info":["metaFile","http://soap.sforce.com/2006/04/metadata",null,"1","1","false"],"metaFile":false,"inFolder_type_info":["inFolder","http://soap.sforce.com/2006/04/metadata",null,"1","1","false"],"inFolder":false,"field_order_type_info":["childXmlNames","directoryName","inFolder","metaFile","suffix","xmlName"],"directoryName_type_info":["directoryName","http://soap.sforce.com/2006/04/metadata",null,"1","1","false"],"directoryName":"labels","childXmlNames_type_info":["childXmlNames","http://soap.sforce.com/2006/04/metadata",null,"0","-1","false"],"childXmlNames":["CustomLabel"],"apex_schema_type_info":["http://soap.sforce.com/2006/04/metadata","true","false"]}]}';

    public static final String ASYNC_JOB = 'ApexClass#Test';

    @TestSetup
    public static void setup() {
        Organisation__c organisation = new Organisation__c(
            Username__c = 'test@test.com',
            User_Full_Name__c = 'test person',
            OwnerId = UserInfo.getUserId()
        );
        insert organisation;

        Tracking_Setting__c trackingOrganizationSetting = new Tracking_Setting__c();
        trackingOrganizationSetting.Organization__c = organisation.Id;
        trackingOrganizationSetting.Is_Processed__c = false;
        trackingOrganizationSetting.Is_Enabled__c = true;
        DatabaseUtils.insertRecord(
            trackingOrganizationSetting,
            new List<Schema.DescribeFieldResult>{
                Tracking_Setting__c.Organization__c.getDescribe(),
                Tracking_Setting__c.Is_Processed__c.getDescribe(),
                Tracking_Setting__c.Is_Enabled__c.getDescribe()
            }
        );

        Repository__c repository = new Repository__c();
        repository.Name = 'repTest';
        insert repository;

        Repository_Permission__c repositoryPermission = new Repository_Permission__c();
        repositoryPermission.Repository__c = repository.Id;
        repositoryPermission.User__c = UserInfo.getUserId();
        insert repositoryPermission;

        Branch__c branch = new Branch__c();
        branch.Branch_Name__c = 'Branch 1';
        branch.Repository__c = repository.Id;
        insert branch;

        List<String> orgComponentIdList = createTestOrgComponents(
            organisation.Id,
            trackingOrganizationSetting.Id,
            5,
            'Retrieved'
        );

        //collection record types
        Map<String, Id> recordTypesMap = new Map<String, Id>();
        String compObjName = Schema.SObjectType.Component__c.getName();
        for (RecordType rt : [
            SELECT Id, Name
            FROM RecordType
            WHERE SobjectType = :compObjName AND (Name = 'Repository' OR Name = 'Branch')
            LIMIT 2
        ]) {
            recordTypesMap.put(rt.Name, rt.Id);
        }

        List<Org_Component__c> orgComponentList = [
            SELECT Component_Type__c, Name__c, CRC32__c
            FROM Org_Component__c
            LIMIT 3
        ];

        List<Component__c> componentList = new List<Component__c>();
        List<Component_History__c> componentHistoryList = new List<Component_History__c>();

        for (Integer i = 0; i < orgComponentList.size(); i++) {
            Org_Component__c orgComponent = orgComponentList.get(i);
            Component__c component = new Component__c();
            component.Version__c = 1;
            component.Component_Type__c = orgComponent.Component_Type__c;
            component.Component_Name__c = orgComponent.Name__c;
            component.File_Name__c = 'Test_Item__C';
            component.RecordTypeId = recordTypesMap.get('Branch');
            component.Branch__c = branch.Id;

            Component_History__c componentHistory = new Component_History__c();
            componentHistory.Version__c = 1;
            componentHistory.CRC32__c = orgComponent.CRC32__c;
            if (i == 1) {
                componentHistory.CRC32__c = '12345678';
            } else if (i == 2) {
                component.RecordTypeId = recordTypesMap.get('Repository');
                component.Repository__c = repository.Id;
            }

            componentList.add(component);
            componentHistoryList.add(componentHistory);
        }

        if (!componentList.isEmpty())
            insert componentList;

        for (Integer i = 0; i < componentHistoryList.size(); i++) {
            componentHistoryList.get(i).Component__c = componentList.get(i).Id;
        }

        if (!componentHistoryList.isEmpty())
            insert componentHistoryList;
    }

    @IsTest
    public static void controllerTest() {
        Organisation__c organisation = [SELECT Id FROM Organisation__c WHERE Username__c = :'test@test.com'];
        PageReference pageRef = Page.UnlockedPackage;
        Test.setCurrentPage(pageRef);
        pageRef.getParameters().put('Id', String.valueOf(organisation.Id));
        ApexPages.StandardController standardController = new ApexPages.StandardController(organisation);
        Test.startTest();
        TrackingOrganizationController controller = new TrackingOrganizationController(standardController);
        controller.sourceId = organisation.Id;
        controller.openCommitToBranch();
        TrackingOrganizationController.getNamespacePrefix();
        TrackingOrganizationController.getSessionId();
        TrackingOrganizationController.getCommitToBranchInfo();
        Test.stopTest();

        System.assertEquals(controller.sourceId, organisation.Id);
    }

    @IsTest
    public static void searchBranchLookupTest() {
        TestDataContainer testDataContainer = new TestDataContainer();

        Test.startTest();
        String result = TrackingOrganizationController.searchBranchLookup(
            new Map<String, Object>{ 'repositoryId' => testDataContainer.repositoryId, 'searchTerm' => 'Branch 1' }
        );
        Test.stopTest();

        List<FlosumUtils.LWCLookupSearchResultWrapper> resultList = (List<FlosumUtils.LWCLookupSearchResultWrapper>) JSON.deserialize(
            result,
            List<FlosumUtils.LWCLookupSearchResultWrapper>.class
        );

        System.assertEquals(1, resultList.size());
        System.assertEquals(testDataContainer.branchIdList.get(0), resultList.get(0).getId());
    }

    @IsTest
    public static void authorizeTest() {
        String authSuccess =
            '{"needToUpdateDetails":true,"isSuccess":true,"infoMessage":"Authentication Successful.","errorMessage":null,"details":' +
            '{"attributes":{"type":"Authorization_Details__c","url":"/services/data/v52.0/sobjects/Authorization_Details__c/a062h000002UmsoAAC"},' +
            '"AuthorisedUser__c":"test-sqjrojr8sd5z@example.com","Name":"00D0t000000K2HW","AccessToken__c":"SESSION_ID_REMOVED","RefreshToken__c"' +
            ':"SESSION_ID_REMOVED","InstanceURL__c":"https://java-saas-3749-dev-ed.cs77.my.salesforce.com","Connected_App_Type__c":"Automatic","Id"' +
            ':"a062h000002UmsoAAC"},"accessType":"Developer"}';
        Test.setMock(HttpCalloutMock.class, new TestMock(authSuccess));

        String authDetail = TrackingOrganizationController.authorize(
            new Map<String, Object>{ 'organizationId' => 'Test' }
        );
        try {
            TrackingOrganizationController.authorize(new Map<String, Object>{ 'not' => 'Test' });
        } catch (Exception e) {
            System.assertEquals(e.getMessage(), 'Field \'organizationId\' not provided!');
        }

        Map<String, Object> authDetailMap = (Map<String, Object>) JSON.deserializeUntyped(authDetail);

        System.assertEquals((Boolean) authDetailMap.get('isSuccess'), false);
    }

    @IsTest
    public static void launchManualRetrieveTest() {
        TestDataContainer testDataContainer = new TestDataContainer();

        Test.startTest();
        String result = TrackingOrganizationController.launchManualRetrieve(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'componentIdList' => JSON.serialize(new List<String>{ 'TestId' })
            }
        );
        Test.stopTest();

        System.assertEquals('true', result);
    }

    @IsTest
    public static void checkSupportedSourceMemberTest() {
        Test.setMock(HttpCalloutMock.class, new TestMock(''));
        String authDetail;
        Test.startTest();
        authDetail = TrackingOrganizationController.checkSupportedSourceMember(
            new Map<String, Object>{ 'accessToken' => 'Test', 'instanceUrl' => 'test' }
        );
        Test.stopTest();
        Map<String, Object> authDetailMap = (Map<String, Object>) JSON.deserializeUntyped(authDetail);

        System.assertEquals((Boolean) authDetailMap.get('isSupported'), true);
    }

    @IsTest
    public static void getSettingsSaveSettingsCheckProcessStateTest() {
        Organisation__c organisation = [SELECT Id FROM Organisation__c WHERE Username__c = :'test@test.com'];
        String settingString = '{"metadataTypeList":["Workflow"],"isEnabled":true,"frequency":"60"}';
        Test.startTest();
        TrackingOrganizationController.getSettings(
            new Map<String, Object>{
                'organizationId' => organisation.Id,
                'metadataTypeOptionList' => '["Workflow"]',
                'frequency' => '5'
            }
        );
        try {
            TrackingOrganizationController.getSettings(
                new Map<String, Object>{ 'metadataTypeOptionList' => '["Workflow"]', 'frequency' => '5' }
            );
        } catch (Exception e) {
            System.assert(e.getMessage() == 'Field \'organizationId\' not provided!');
        }

        TrackingOrganizationController.saveSettings(
            new Map<String, Object>{ 'settings' => settingString, 'organizationId' => organisation.Id }
        );
        String state = TrackingOrganizationController.checkProcessState(
            new Map<String, Object>{ 'organizationId' => organisation.Id }
        );
        Test.stopTest();

        System.assert(![SELECT Id FROM Tracking_Setting__c].isEmpty());
        System.assert(state == 'Success');
    }

    @IsTest
    public static void getSettingsWithNullTrackingSetting() {
        TestDataContainer testDataContainer = new TestDataContainer();
        List<Tracking_Setting__c> trackingSettingList = [
            SELECT Id
            FROM Tracking_Setting__c
            WHERE Organization__c = :testDataContainer.organisationId
        ];
        if (!trackingSettingList.isEmpty()) {
            delete trackingSettingList;
        } else {
            throw new FlosumException('trackingSettingList is Empty');
        }
        System.assertEquals(
            [SELECT Id FROM Tracking_Setting__c WHERE Organization__c = :testDataContainer.organisationId].size(),
            0
        );
        Test.startTest();
        TrackingOrganizationController.getSettings(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'metadataTypeOptionList' => '["Workflow"]',
                'frequency' => '5'
            }
        );
        Test.stopTest();
        System.assertEquals(
            [SELECT Id FROM Tracking_Setting__c WHERE Organization__c = :testDataContainer.organisationId].size(),
            1
        );
    }

    @IsTest
    public static void getRelatedListOrgComponentsIdTest() {
        Test.setMock(
            HttpCalloutMock.class,
            new TrackingOrganizationControllerTest.TestMock(
                '{"size":1,"totalSize":1,"done":true,"queryLocator":null,"entityTypeName":"CustomField","records":[{"attributes":{"type":"CustomField","url":"/services/data/v51.0/tooling/sobjects/CustomField/00NN000000CYeAgMAL"},"Id":"00NN000000CYeAgMAL","DeveloperName":"OrganisationName","EntityDefinitionId":"01IN000000145KI"}]}'
            )
        );

        Test.startTest();
        String id = TrackingOrganizationController.getRelatedListOrgComponentsId();
        Test.stopTest();

        System.assertEquals('00NN000000CYeAg', id);
    }

    @IsTest
    public static void getLatestComponentsTest() {
        TestDataContainer testDataContainer = new TestDataContainer();
        createTestOrgComponents(
            testDataContainer.organisationId,
            testDataContainer.trackingSettingId,
            200,
            'Retrieved'
        );

        Test.startTest();
        String componentsLatest = TrackingOrganizationController.getLatestComponents(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'lastId' => '',
                'isAll' => false
            }
        );
        String componentsAll = TrackingOrganizationController.getLatestComponents(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'lastId' => '',
                'isAll' => true
            }
        );
        Test.stopTest();

        List<TrackingService.SourceMemberWrapper> componentsLatestList = (List<TrackingService.SourceMemberWrapper>) JSON.deserialize(
            componentsLatest,
            List<TrackingService.SourceMemberWrapper>.class
        );

        List<TrackingService.SourceMemberWrapper> componentsAllList = (List<TrackingService.SourceMemberWrapper>) JSON.deserialize(
            componentsAll,
            List<TrackingService.SourceMemberWrapper>.class
        );

        System.assertEquals(10, componentsLatestList.size());
        System.assertEquals(205, componentsAllList.size());
    }

    @IsTest
    public static void launchRetrieveTest() {
        Datetime dt = Datetime.now().addMinutes(5);
        String scheduleExpression = String.format(
            '{0} {1} {2} {3} {4} ? {5}',
            new List<Integer>{ dt.second(), dt.minute(), dt.hour(), dt.day(), dt.month(), dt.year() }
        );

        TrackingAutomationScheduler trackingAutomationScheduler = new TrackingAutomationScheduler();

        System.schedule(
            TrackingService.TRACKING_SCHEDULER_NAME + ' Test',
            scheduleExpression,
            trackingAutomationScheduler
        );

        Test.startTest();
        TrackingOrganizationController.launchRetrieve();
        Test.stopTest();

        System.assert(
            [
                    SELECT Id
                    FROM CronTrigger
                    WHERE
                        (CronJobDetail.Name LIKE :TrackingService.TRACKING_SCHEDULER_NAME + ' Test'
                        AND CronJobDetail.Name != :TrackingService.TRACKING_SCHEDULER_NAME
                        AND State != 'EXECUTING')
                        OR (CronJobDetail.Name LIKE :TrackingService.TRACKING_SCHEDULER_NAME + ' Test'
                        AND State = 'DELETED')
                ]
                .isEmpty()
        );
    }

    @IsTest
    public static void createLogTest() {
        TestDataContainer testDataContainer = new TestDataContainer();
        Test.startTest();
        String log = TrackingOrganizationController.createLog(
            new Map<String, Object>{ 'organizationId' => testDataContainer.organisationId }
        );
        Test.stopTest();

        TrackingService.LogWrapper logWrapper = (TrackingService.LogWrapper) JSON.deserialize(
            log,
            TrackingService.LogWrapper.class
        );

        System.assertNotEquals(null, logWrapper);
    }

    @IsTest
    public static void getMetadataTypeListTest() {
        insert new List<FlosumSetting__c>{
            new FlosumSetting__c(
                Name = 'Test1',
                Metadata_Type_Name__c = 'ApexClass',
                is_Enabled__c = true,
                Configuration_Only__c = false
            ),
            new FlosumSetting__c(
                Name = 'Test2',
                Metadata_Type_Name__c = 'ApexPage',
                is_Enabled__c = true,
                Configuration_Only__c = false
            )
        };

        Test.startTest();
        String metaListString = TrackingOrganizationController.getMetadataTypeList(
            new Map<String, Object>{ 'accessToken' => 'Test', 'instanceUrl' => 'test' }
        );
        Test.stopTest();
        List<String> metaList = (List<String>) JSON.deserialize(metaListString, List<String>.class);

        System.assertEquals(metaList.size(), 2);
    }

    @IsTest
    public static void getSourceMembersTest() {
        Test.setMock(
            HttpCalloutMock.class,
            new TestMock(
                '{"records":[{"attributes":{"type":"SourceMember","url":"/services/data/v51.0/tooling/sobjects/SourceMember/0MZ0t00000JHCJtGAP"},"MemberType":"Workflow","IsNameObsolete":false,"MemberIdOrName":"01I0t000001KKodEAG","MemberName":"Branch__c","RevisionCounter":3112},{"attributes":{"type":"SourceMember","url":"/services/data/v51.0/tooling/sobjects/SourceMember/0MZ0t00000JHCJuGAP"},"MemberType":"Workflow","IsNameObsolete":false,"MemberIdOrName":"01I0t000001KKofEAG","MemberName":"Build__c","RevisionCounter":3113},{"attributes":{"type":"SourceMember","url":"/services/data/v51.0/tooling/sobjects/SourceMember/0MZ0t00000JHCJvGAP"},"MemberType":"Workflow","IsNameObsolete":false,"MemberIdOrName":"01I0t000001KKoiEAG","MemberName":"Commit__c","RevisionCounter":3114}]}'
            )
        );

        Organisation__c organisation = [SELECT Id FROM Organisation__c WHERE Username__c = :'test@test.com'];

        Test.startTest();
        String sourceMemberPacksString = TrackingOrganizationController.getSourceMembers(
            new Map<String, Object>{
                'organizationId' => organisation.Id,
                'accessToken' => 'Test',
                'instanceUrl' => 'test'
            }
        );
        Test.stopTest();
        System.debug(sourceMemberPacksString);
        TrackingService.SourceMemberPacksWrapper sourceMemberPacksWrapper = (TrackingService.SourceMemberPacksWrapper) JSON.deserialize(
            sourceMemberPacksString,
            TrackingService.SourceMemberPacksWrapper.class
        );

        System.assertEquals(sourceMemberPacksWrapper.changedList.size(), 3);
    }

    @IsTest
    public static void getUserNamesTest() {
        String body = '[{"attributes":{"type":"User","url":"/services/data/v51.0/tooling/sobjects/User/0050t000007pqkDAAQ"},"Id":"0050t000007pqkDAAQ","Name":"User User"}]';
        Test.setMock(HttpCalloutMock.class, new TestMock(body));

        Organisation__c organisation = [SELECT Id FROM Organisation__c WHERE Username__c = :'test@test.com'];

        Test.startTest();
        String userString = TrackingOrganizationController.getUserNames(
            new Map<String, Object>{
                'organizationId' => organisation.Id,
                'accessToken' => 'Test',
                'userIds' => '0050t000007pqkDAAQ'
            }
        );
        Test.stopTest();
        System.debug('userString ' + userString);

        System.assertEquals(body, userString);
    }

    @IsTest
    public static void createLogGetLogsGetLogBodyTest() {
        TestDataContainer testDataContainer = new TestDataContainer();
        Test.startTest();
        testDataContainer.logger.addLine('Test Log Body');
        testDataContainer.logger.updateLog();

        String logListString = TrackingOrganizationController.getLogs(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'countLeft' => '1',
                'logIdAlreadyRetrievedList' => '[]'
            }
        );

        List<TrackingService.LogWrapper> logList = (List<TrackingService.LogWrapper>) JSON.deserialize(
            logListString,
            List<TrackingService.LogWrapper>.class
        );
        String logOneString = TrackingOrganizationController.getLog(
            new Map<String, Object>{ 'metadataLogId' => logList.get(0).id }
        );
        String logBody = TrackingOrganizationController.getLogBody(
            new Map<String, Object>{ 'metadataLogId' => logList.get(0).id }
        );
        Test.stopTest();
        System.assertEquals(logList.size(), 1);
        System.assert(logBody.contains('Test Log Body'));
        System.assert(String.isNotBlank(logOneString));
    }

    @IsTest
    public static void pullChangesTest() {
        TestDataContainer testDataContainer = new TestDataContainer();
        Test.startTest();

        String componentListString =
            '[{"type":"ApexClass","componentList":[{"sourceMemberId":null,' +
            '"revisionCounter":3200,"isNew":false,"isDeleted":false,"id":"01p0t00000Aw7h7AAB",' +
            '"componentType":"ApexClass","componentName":"TestController","changedById":"0050t000007pqkD",' +
            '"changedBy":"User User","asyncJobId":null,"changedAction":"Changed","checked":true},' +
            '{"sourceMemberId":null,"revisionCounter":3200,"isNew":false,"isDeleted":true,"id":"01p0t00000Aw7h7AAB",' +
            '"componentType":"ApexClass","componentName":"TestController","changedById":"0050t000007pqkD","changedBy":"User User",' +
            '"asyncJobId":null,"changedAction":"Changed","checked":true}]}]';

        String resultError = TrackingOrganizationController.pullChanges(
            new Map<String, Object>{
                'metadataLogId' => testDataContainer.logger.parentId,
                'isFirst' => true,
                'isLast' => true,
                'organizationId' => ''
            }
        );

        String resultSuccess = TrackingOrganizationController.pullChanges(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'isFirst' => true,
                'isLast' => true,
                'metadataLogId' => testDataContainer.logger.parentId,
                'componentList' => componentListString
            }
        );
        Test.stopTest();

        Map<String, Object> resultSuccessMap = (Map<String, Object>) JSON.deserializeUntyped(resultSuccess);
        Map<String, Object> resultErrorMap = (Map<String, Object>) JSON.deserializeUntyped(resultError);

        System.assert((Boolean) resultSuccessMap.get('isSuccess'));
        System.assert(!(Boolean) resultErrorMap.get('isSuccess'));
    }

    @IsTest
    public static void getCommitToBranchOptionsTest() {
        TestDataContainer testDataContainer = new TestDataContainer();

        Test.startTest();
        String result = TrackingOrganizationController.getCommitToBranchOptions(
            new Map<String, Object>{ 'organizationId' => testDataContainer.organisationId }
        );
        Test.stopTest();

        System.assert(result.contains(testDataContainer.repositoryId));
    }

    @IsTest
    public static void checkCommitPermissionsTest() {
        TestDataContainer testDataContainer = new TestDataContainer();

        Test.startTest();
        String result = TrackingOrganizationController.checkCommitPermissions(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'repositoryId' => testDataContainer.repositoryId,
                'branchName' => 'Branch 1',
                'branchId' => testDataContainer.branchIdList.get(0)
            }
        );
        String resultNewBranch = TrackingOrganizationController.checkCommitPermissions(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'repositoryId' => testDataContainer.repositoryId,
                'branchName' => 'Branch 2',
                'branchId' => ''
            }
        );
        Test.stopTest();

        System.assertEquals(testDataContainer.branchIdList.get(0), result);
        System.assertNotEquals(testDataContainer.branchIdList.get(0), resultNewBranch);
    }

    // Test: getOrgComponentsInfo, getAttachmentsInfo, getAttachmentsBody
    @IsTest
    public static void getOrgComponentsAndAttachmentsInfoTest() {
        TestDataContainer testDataContainer = new TestDataContainer();

        List<String> attachmentIdList = new List<String>();
        for (Org_Component__c component : [
            SELECT Attachment_ID__c
            FROM Org_Component__c
            WHERE Id IN :testDataContainer.orgComponentIdList
        ]) {
            attachmentIdList.add(component.Attachment_ID__c);
        }

        Test.startTest();
        String resultOrgComponent = TrackingOrganizationController.getOrgComponentsInfo(
            new Map<String, Object>{ 'orgComponentIdListJson' => JSON.serialize(testDataContainer.orgComponentIdList) }
        );
        String resultAttachment = TrackingOrganizationController.getAttachmentsInfo(
            new Map<String, Object>{ 'attachmentIdListJson' => JSON.serialize(attachmentIdList) }
        );
        List<TrackingOrganizationController.AttachmentWrapper> attachmentBodyWrapperList = TrackingOrganizationController.getAttachmentsBody(
            new Map<String, Object>{ 'attachmentIdListJson' => JSON.serialize(attachmentIdList) }
        );
        Test.stopTest();

        List<TrackingOrganizationController.OrgComponentWrapper> orgComponentWrapperList = (List<TrackingOrganizationController.OrgComponentWrapper>) JSON.deserialize(
            resultOrgComponent,
            List<TrackingOrganizationController.OrgComponentWrapper>.class
        );

        List<TrackingOrganizationController.AttachmentWrapper> attachmentWrapperList = (List<TrackingOrganizationController.AttachmentWrapper>) JSON.deserialize(
            resultAttachment,
            List<TrackingOrganizationController.AttachmentWrapper>.class
        );

        System.assertEquals(5, orgComponentWrapperList.size());
        System.assertEquals(5, attachmentWrapperList.size());
        System.assertEquals(5, attachmentBodyWrapperList.size());
    }

    @IsTest
    public static void compareOrgComponentsAndBranchComponentsTest() {
        TestDataContainer testDataContainer = new TestDataContainer();

        Map<String, String> orgComponentIdCrcMap = new Map<String, String>();
        for (Integer i = 0; i < testDataContainer.orgComponentIdList.size(); i++) {
            orgComponentIdCrcMap.put(testDataContainer.orgComponentIdList.get(i), '' + i);
        }

        Test.startTest();
        String result = TrackingOrganizationController.compareOrgComponentsAndBranchComponents(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'branchId' => testDataContainer.branchIdList.get(0),
                'orgComponentIdToCrcCodeMapJson' => JSON.serialize(orgComponentIdCrcMap)
            }
        );
        Test.stopTest();

        TrackingOrganizationController.CompareResultWrapper compareResultWrapper = (TrackingOrganizationController.CompareResultWrapper) JSON.deserialize(
            result,
            TrackingOrganizationController.CompareResultWrapper.class
        );

        System.debug('result ' + result);
        System.assert(compareResultWrapper.conflictCommit.isEmpty());
        System.assert(!compareResultWrapper.notCommitList.isEmpty());
        System.assert(!compareResultWrapper.safeCommit.isEmpty());
    }

    @IsTest
    public static void setBranchProcessedTest() {
        TestDataContainer testDataContainer = new TestDataContainer();

        Test.startTest();
        TrackingOrganizationController.setBranchProcessed(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'branchId' => testDataContainer.branchIdList.get(0)
            }
        );
        Test.stopTest();

        Branch__c branch = [SELECT Status__c FROM Branch__c WHERE Id = :testDataContainer.branchIdList.get(0)];
        System.assertEquals('In Progress', branch.Status__c);
    }

    @IsTest
    public static void commitToBranchTest() {
        TestDataContainer testDataContainer = new TestDataContainer();

        List<Org_Component__c> orgComponentList = [
            SELECT Id, API_Name__c, Component_Type__c
            FROM Org_Component__c
            WHERE Id IN :testDataContainer.orgComponentIdList
        ];

        Map<String, TrackingOrganizationController.CommitToBranchComponentWrapper> orgComponentIdToDataMap = new Map<String, TrackingOrganizationController.CommitToBranchComponentWrapper>();
        for (Integer i = 0; i < orgComponentList.size(); i++) {
            String key = orgComponentList.get(i).Component_Type__c + '#' + orgComponentList.get(i).API_Name__c;
            TrackingOrganizationController.CommitToBranchComponentWrapper commitToBranchComponentWrapper = new TrackingOrganizationController.CommitToBranchComponentWrapper();
            commitToBranchComponentWrapper.attachmentId = 'Test attachmentId' + i;
            commitToBranchComponentWrapper.crc32 = '' + i;
            orgComponentIdToDataMap.put(key, commitToBranchComponentWrapper);
        }

        TrackingOrganizationController.CommitToBranchWrapper commitToBranchWrapper = new TrackingOrganizationController.CommitToBranchWrapper();
        commitToBranchWrapper.attachmentIdList = new List<String>();
        commitToBranchWrapper.orgComponentIdList = testDataContainer.orgComponentIdList;
        commitToBranchWrapper.organizationId = testDataContainer.organisationId;
        commitToBranchWrapper.organizationName = 'Test Org Name';
        commitToBranchWrapper.branchId = testDataContainer.branchIdList.get(0);
        commitToBranchWrapper.orgComponentIdToDataMap = orgComponentIdToDataMap;

        Test.startTest();
        TrackingOrganizationController.prepareToCommit(commitToBranchWrapper.branchId);
        TrackingOrganizationController.commitToBranch(JSON.serialize(commitToBranchWrapper));
        TrackingOrganizationController.completeCommit(commitToBranchWrapper.branchId);
        Test.stopTest();

        TestResultDataContainer testResultDataContainer = new TestResultDataContainer(
            testDataContainer.trackingSettingId
        );

        System.assertEquals(5, testResultDataContainer.sizeComponentsAll);
    }

    @IsTest
    public static void updateLogTest() {
        TestDataContainer testDataContainer = new TestDataContainer();
        Test.startTest();
        String result = TrackingOrganizationController.updateLog(
            new Map<String, Object>{
                'parentId' => testDataContainer.logger.parentId,
                'logFile' => JSON.serialize(new List<String>{ 'Test Log 1', 'Test Log 2' })
            }
        );
        Test.stopTest();
        System.assertEquals('true', result);
    }

    //need to finish the tests
    @IsTest
    public static void manualRetrieveTest() {
        TestDataContainer testDataContainer = new TestDataContainer();
        createTestOrgComponents(
            testDataContainer.organisationId,
            testDataContainer.trackingSettingId,
            1,
            'In Progress',
            new List<String>{ 'Profile' }
        );

        Tracking_Setting__c trackingSetting = [
            SELECT Id
            FROM Tracking_Setting__c
            WHERE Id = :testDataContainer.trackingSettingId
        ];
        trackingSetting.Is_Processed__c = true;
        trackingSetting.Current_Jobs__c = 'TestId';
        trackingSetting.Current_Apex_Job_Id__c = 'TestIdApexJob';
        update trackingSetting;

        Attachment orgAttachment = new Attachment();
        orgAttachment.ParentId = testDataContainer.organisationId;
        orgAttachment.Name = 'TestId';
        orgAttachment.ContentType = 'application/zip';
        orgAttachment.Body = EncodingUtil.base64Decode('Test Body');
        orgAttachment.Description = 'Profile';
        insert orgAttachment;

        Test.startTest();
        String orgComponentsString = TrackingOrganizationController.getOrgComponentsForManualRetrieve(
            new Map<String, Object>{ 'organizationId' => testDataContainer.organisationId }
        );
        String trackingSettingAbortJob = TrackingOrganizationController.trackingSettingAbortJob(
            new Map<String, Object>{ 'organizationId' => testDataContainer.organisationId }
        );
        String updateTooLargeComponents = TrackingOrganizationController.updateTooLargeComponents(
            new Map<String, Object>{ 'organizationId' => testDataContainer.organisationId }
        );
        String finishManualRetrieve = TrackingOrganizationController.finishManualRetrieve(
            new Map<String, Object>{
                'organizationId' => testDataContainer.organisationId,
                'parentId' => testDataContainer.logger.parentId,
                'finishMessage' => 'Test Retrieve Completed.'
            }
        );
        Test.stopTest();

        TestResultDataContainer testResultDataContainer = new TestResultDataContainer(
            testDataContainer.trackingSettingId
        );

        List<TrackingOrganizationController.OrgComponentWrapper> OrgComponentsList = (List<TrackingOrganizationController.OrgComponentWrapper>) JSON.deserialize(
            orgComponentsString,
            List<TrackingOrganizationController.OrgComponentWrapper>.class
        );
        System.assertEquals(1, OrgComponentsList.size());
        System.assertEquals('true', trackingSettingAbortJob);
        System.assertEquals('true', updateTooLargeComponents);
        System.assertEquals('true', finishManualRetrieve);

        System.assert(String.isBlank(testResultDataContainer.currentApexJobId));
        System.assert(String.isBlank(testResultDataContainer.currentJobs));
        System.assertEquals(false, testResultDataContainer.isProcessed);
        System.assertEquals(0, testResultDataContainer.sizeOrgComponentsInProgress);
    }

    @IsTest
    public static void createBranchActivityTest() {
        TestDataContainer testDataContainer = new TestDataContainer();
        Test.startTest();
        String result = TrackingOrganizationController.createBranchActivity(
            new Map<String, Object>{
                'type' => 'commitToBranch',
                'organizationId' => testDataContainer.organisationId,
                'branchId' => testDataContainer.branchIdList.get(0),
                'idsList' => JSON.serialize(testDataContainer.orgComponentIdList)
            }
        );
        Test.stopTest();
        System.debug('result = ' + result);
        System.assertEquals('true', result);
    }

    @IsTest
    public static void integrateWithExternalServices() {
        TestDataContainer testDataContainer = new TestDataContainer();
        Test.startTest();
        TrackingOrganizationController.createBranchActivity(
            new Map<String, Object>{
                'branchId' => testDataContainer.branchIdList.get(0),
                'idsList' => JSON.serialize(testDataContainer.orgComponentIdList)
            }
        );
        Test.stopTest();
        System.assert(true);
    }

    @IsTest
    public static void updateComponentsWithDependenciesTest() {
        Org_Component__c orgComponent = [SELECT Id, Attachment_ID__c FROM Org_Component__c LIMIT 1];
        String dependencyComponentJson = '{"attachmentId":"'+orgComponent.Attachment_ID__c+'","body":"Test"}';

        Test.startTest();
        TrackingOrganizationController.updateComponentsWithDependencies(dependencyComponentJson);
        Test.stopTest();
        
        System.assertEquals([SELECT Body FROM Attachment WHERE Id =: orgComponent.Attachment_ID__c].Body, EncodingUtil.base64Decode('Test'));
    }

    ////////// UTILS METHODS AND CLASSES
    public static List<String> createTestOrgComponents(
        String organizationId,
        String trackingSettingId,
        Integer countRecords
    ) {
        return createTestOrgComponents(
            organizationId,
            trackingSettingId,
            countRecords,
            'Pending',
            new List<String>{ 'ApexClass' }
        );
    }

    public static List<String> createTestOrgComponents(
        String organizationId,
        String trackingSettingId,
        Integer countRecords,
        String status
    ) {
        return createTestOrgComponents(
            organizationId,
            trackingSettingId,
            countRecords,
            status,
            new List<String>{ 'ApexClass' }
        );
    }

    public static List<String> createTestOrgComponents(
        String organizationId,
        String trackingSettingId,
        Integer countRecords,
        String status,
        List<String> typeList
    ) {
        List<Org_Component__c> orgComponentList = new List<Org_Component__c>();
        Map<String, Attachment> attachmentMap = new Map<String, Attachment>();

        for (Integer i = 0; i < countRecords; i++) {
            Org_Component__c orgComponent;

            String type = typeList.size() > i ? typeList.get(i) : typeList.get(typeList.size() - 1);

            orgComponent = new Org_Component__c();
            orgComponent.OrganisationName__c = organizationId;
            orgComponent.Tracking_Setting__c = trackingSettingId;
            orgComponent.API_Name__c = 'TestOrgComponent' + i;
            orgComponent.Name__c = 'TestOrgComponent' + i;
            orgComponent.Source_Member_Id__c = 'TestOrgComponent' + i;
            orgComponent.Component_Type__c = type;
            orgComponent.Label__c = typeFolderMap.get(type) + '/TestOrgComponent' + i + '.' + typeSuffixMap.get(type);
            orgComponent.New_Revision_Counter__c = i;
            orgComponent.Is_Deleted__c = false;
            orgComponent.Is_Processed__c = false;
            orgComponent.Is_Retrieved__c = false;
            orgComponent.Status__c = status;
            orgComponent.Async_Job_Id__c = 'TestId';

            if (orgComponent.Status__c.equals('Retrieved')) {
                orgComponent.Is_Processed__c = false;
                orgComponent.Revision_Counter__c = orgComponent.New_Revision_Counter__c;
                orgComponent.New_Revision_Counter__c = null;
                orgComponent.Async_Job_Id__c = null;
                orgComponent.Attachment_ID__c = '' + i;
                orgComponent.CRC32__c = '' + i;

                Attachment orgAttachment = new Attachment();
                orgAttachment.ParentId = organizationId;
                orgAttachment.Name = orgComponent.Name__c;
                orgAttachment.ContentType = 'application/zip';
                orgAttachment.Body = EncodingUtil.base64Decode('Test Body' + i);
                orgAttachment.Description = orgComponent.Component_Type__c;
                attachmentMap.put(orgAttachment.Name, orgAttachment);
            } else if (orgComponent.Is_Deleted__c) {
                orgComponent.Is_Processed__c = false;
                orgComponent.Status__c = 'Deleted';
                orgComponent.Revision_Counter__c = orgComponent.New_Revision_Counter__c;
                orgComponent.New_Revision_Counter__c = null;
                orgComponent.Async_Job_Id__c = null;
            } else {
                orgComponent.Is_Processed__c = true;
                orgComponent.Status__c = 'In Progress';
            }

            orgComponentList.add(orgComponent);
        }

        if (!attachmentMap.isEmpty()) {
            insert attachmentMap.values();

            for (Org_Component__c component : orgComponentList) {
                if (attachmentMap.containsKey(component.Name__c)) {
                    component.Attachment_ID__c = attachmentMap.get(component.Name__c).Id;
                }
            }
        }

        if (!orgComponentList.isEmpty()) {
            insert orgComponentList;
        }

        List<String> orgComponentIdList = new List<String>();
        for (Org_Component__c component : orgComponentList) {
            orgComponentIdList.add(component.Id);
        }

        return orgComponentIdList;
    }

    public class TestDataContainer {
        public TrackingService.Logger logger;
        public List<String> branchIdList;
        public List<String> orgComponentIdList;
        public String organisationId;
        public String trackingSettingId;
        public String repositoryId;
        public String accessToken;
        public String instanceUrl;

        public TestDataContainer() {
            Organisation__c organisation = [SELECT Id FROM Organisation__c WHERE Username__c = :'test@test.com'];
            TrackingService.Logger logger = null;
            List<String> branchIdList = new List<String>();
            List<String> orgComponentIdList = new List<String>();
            String trackingSettingId = '';
            String repositoryId = '';

            // accessToken, instanceUrl
            AuthUtils.AuthenticateDetails authDetails = AuthUtils.authenticateAnOrg(
                organisation.Id,
                FlosumConstants.DEVELOPER
            );

            // trackingSettingId, logger
            List<Tracking_Setting__c> trackingOrganizationSettingList = [
                SELECT
                    Id,
                    Name,
                    Is_Processed__c,
                    Organization__c,
                    Organization__r.Name,
                    Current_Jobs__c,
                    Metadata_Types__c
                FROM Tracking_Setting__c
                WHERE Organization__c = :organisation.Id
            ];

            if (!trackingOrganizationSettingList.isEmpty()) {
                Metadata_Log__c metadataLog = TrackingService.createLog(
                    organisation.Id,
                    trackingOrganizationSettingList.get(0).Id,
                    TrackingService.PROCESS_TYPE_RETRIEVE_ORGANIZATION,
                    TrackingService.TRACKING_ORGANIZATION_LOG_NAME
                );

                logger = new TrackingService.Logger(metadataLog.Id, TrackingService.TRACKING_ORGANIZATION_LOG_NAME);
                trackingSettingId = trackingOrganizationSettingList.get(0).Id;
            }

            // repositoryId, branchIdList
            List<Repository__c> repositoryList = [SELECT Id FROM Repository__c WHERE Name = :'repTest'];
            if (!repositoryList.isEmpty()) {
                repositoryId = repositoryList.get(0).Id;
                Map<Id, Branch__c> branchMap = new Map<Id, Branch__c>(
                    [SELECT Id FROM Branch__c WHERE Repository__c = :repositoryId]
                );
                if (!branchMap.isEmpty()) {
                    branchIdList.addAll(new List<Id>(branchMap.keySet()));
                }
            }

            // orgComponentIdList
            for (Org_Component__c orgComponent : [
                SELECT Id
                FROM Org_Component__c
                WHERE OrganisationName__c = :organisation.Id
            ]) {
                orgComponentIdList.add(orgComponent.Id);
            }

            this.logger = logger;
            this.branchIdList = branchIdList;
            this.orgComponentIdList = orgComponentIdList;
            this.organisationId = organisation.Id;
            this.trackingSettingId = trackingSettingId;
            this.repositoryId = repositoryId;
            this.accessToken = authDetails.details.AccessToken__c;
            this.instanceUrl = authDetails.details.InstanceURL__c;
        }

        public void prepareToLaunch() {
            List<Tracking_Setting__c> trackingOrganizationSettingList = [
                SELECT
                    Id,
                    Name,
                    Is_Processed__c,
                    Organization__c,
                    Organization__r.Name,
                    Current_Jobs__c,
                    Metadata_Types__c
                FROM Tracking_Setting__c
                LIMIT 1
            ];
            if (!trackingOrganizationSettingList.isEmpty()) {
                trackingOrganizationSettingList.get(0).Last_Start_Retrieval__c = Datetime.now()
                    .addMinutes(-5)
                    .addSeconds(-2);
                trackingOrganizationSettingList.get(0).Is_Enabled__c = true;

                update trackingOrganizationSettingList;
            }
        }
    }

    public class TestResultDataContainer {
        public Integer sizeComponentsAll;
        public Integer sizeOrgComponentsAll;
        public Integer sizeOrgComponentsError;
        public Integer sizeOrgComponentsRetrieved;
        public Integer sizeOrgComponentsTooLarge;
        public Integer sizeOrgComponentsInProgress;
        public Integer sizeOrgComponentsDeleted;
        public String currentJobs;
        public String currentApexJobId;
        public Boolean isProcessed;

        public TestResultDataContainer(String trackingSettingId) {
            sizeComponentsAll = [SELECT Id FROM Component__c].size();
            sizeOrgComponentsAll = [SELECT Id FROM Org_Component__c WHERE Tracking_Setting__c = :trackingSettingId]
                .size();
            sizeOrgComponentsError = [
                    SELECT Id
                    FROM Org_Component__c
                    WHERE Tracking_Setting__c = :trackingSettingId AND Status__c = 'Error'
                ]
                .size();
            sizeOrgComponentsRetrieved = [
                    SELECT Id
                    FROM Org_Component__c
                    WHERE Tracking_Setting__c = :trackingSettingId AND Status__c = 'Retrieved'
                ]
                .size();
            sizeOrgComponentsTooLarge = [
                    SELECT Id
                    FROM Org_Component__c
                    WHERE Tracking_Setting__c = :trackingSettingId AND Status__c = 'Too Large'
                ]
                .size();
            sizeOrgComponentsInProgress = [
                    SELECT Id
                    FROM Org_Component__c
                    WHERE Tracking_Setting__c = :trackingSettingId AND Status__c = 'In Progress'
                ]
                .size();
            sizeOrgComponentsDeleted = [
                    SELECT Id
                    FROM Org_Component__c
                    WHERE Tracking_Setting__c = :trackingSettingId AND Status__c = 'Deleted'
                ]
                .size();

            Tracking_Setting__c trackingSetting = [
                SELECT Is_Processed__c, Current_Jobs__c, Current_Apex_Job_Id__c
                FROM Tracking_Setting__c
                WHERE Id = :trackingSettingId
            ];
            isProcessed = trackingSetting.Is_Processed__c;
            currentJobs = trackingSetting.Current_Jobs__c;
            currentApexJobId = trackingSetting.Current_Apex_Job_Id__c;
        }
    }

    public class TestMock implements HttpCalloutMock {
        private String body = '';
        private Map<String, String> endpointResponseMap = null;

        private Integer statusCode = 200;
        private String status = 'OK';

        public TestMock(String body) {
            this.body = body;
        }

        public TestMock(Map<String, String> endpointResponseMap) {
            this.endpointResponseMap = endpointResponseMap;
        }

        public HttpResponse respond(HttpRequest req) {
            if (endpointResponseMap != null) {
                String requestEndpoint = req.getEndpoint();
                Set<String> endpointSet = endpointResponseMap.keySet();
                for (String endpoint : endpointSet) {
                    if (requestEndpoint.contains(endpoint)) {
                        body = endpointResponseMap.get(endpoint);
                        break;
                    }
                }
            }
            HttpResponse res = new HttpResponse();
            res.setBody(body);
            res.setStatusCode(statusCode);
            res.setStatus(status);
            return res;
        }
    }

    public class WebServiceMockImpl implements WebServiceMock {
        private Boolean isLimitError;
        private Boolean isCalloutException;
        private Boolean isDone;
        private Boolean isFolder;
        private Boolean isDependency;

        public WebServiceMockImpl() {
            isLimitError = false;
            isDone = true;
            isFolder = false;
            isDependency = false;
        }

        public WebServiceMockImpl(Map<String, Object> dataMap) {
            this.isFolder = dataMap.containsKey('isFolder') ? (Boolean) dataMap.get('isFolder') : false;
            this.isDependency = dataMap.containsKey('isDependency') ? (Boolean) dataMap.get('isDependency') : false;
            this.isLimitError = dataMap.containsKey('isLimitError') ? (Boolean) dataMap.get('isLimitError') : false;
            this.isCalloutException = dataMap.containsKey('isCalloutException')
                ? (Boolean) dataMap.get('isCalloutException')
                : false;
            this.isDone = dataMap.containsKey('isDone') ? (Boolean) dataMap.get('isDone') : true;
        }

        public void doInvoke(
            Object stub,
            Object request,
            Map<String, Object> response,
            String endpoint,
            String soapAction,
            String requestName,
            String responseNS,
            String responseName,
            String responseType
        ) {
            System.debug('Invoke WebServiceMockImpl, requestName = "' + requestName + '"');

            if (requestName == 'listMetadata') {
                String type = 'ApexClass';
                if (isFolder) {
                    type = 'Document';
                } else if (isDependency) {
                    type = 'QuickAction';
                }
                String folder = typeFolderMap.get(type);
                String suffix = typeSuffixMap.get(type);

                MetadataService.listMetadataResponse_element listMetadataResponseElement = new MetadataService.listMetadataResponse_element();
                List<MetadataService.FileProperties> filePropertiesList = new List<MetadataService.FileProperties>();

                MetadataService.FileProperties fileProperties = new MetadataService.FileProperties();
                fileProperties.lastModifiedDate = Datetime.now();
                fileProperties.lastModifiedByName = 'Test';
                fileProperties.fileName = folder + '/TestOrgComponent0.' + suffix;
                fileProperties.fullName = 'TestOrgComponent0';
                fileProperties.type_x = type;

                MetadataService.FileProperties fileProperties2 = new MetadataService.FileProperties();
                fileProperties2.lastModifiedDate = Datetime.now();
                fileProperties2.lastModifiedByName = 'Test';
                fileProperties2.fileName = folder + '/TestOrgComponent1.' + suffix;
                fileProperties2.fullName = 'TestOrgComponent1';
                fileProperties2.type_x = type;
                filePropertiesList.add(fileProperties);

                listMetadataResponseElement.result = filePropertiesList;
                response.put('response_x', listMetadataResponseElement);
            }

            if (requestName == 'createMetadata') {
                MetadataService.createMetadataResponse_element metadataResponseElement = new MetadataService.createMetadataResponse_element();
                List<MetadataService.SaveResult> saveResultsList = new List<MetadataService.SaveResult>();
                MetadataService.SaveResult saveResult = new MetadataService.SaveResult();
                saveResult.success = true;
                saveResultsList.add(saveResult);
                metadataResponseElement.result = saveResultsList;
                response.put('response_x', metadataResponseElement);
            }

            if (requestName == 'updateMetadata') {
                MetadataService.updateMetadataResponse_element metadataResponseElement = new MetadataService.updateMetadataResponse_element();
                List<MetadataService.SaveResult> saveResultsList = new List<MetadataService.SaveResult>();
                MetadataService.SaveResult saveResult = new MetadataService.SaveResult();
                saveResult.success = true;
                saveResultsList.add(saveResult);
                metadataResponseElement.result = saveResultsList;
                response.put('response_x', metadataResponseElement);
            }

            if (requestName == 'deploy') {
                MetadataService.deployResponse_element response_x = new MetadataService.deployResponse_element();
                MetadataService.AsyncResult asyncResult = new MetadataService.AsyncResult();
                asyncResult.done = true;
                asyncResult.id = 'deployId';
                response_x.result = asyncResult;
                response.put('response_x', response_x);
            }

            if (requestName == 'retrieve') {
                MetadataService.retrieveResponse_element response_x = new MetadataService.retrieveResponse_element();
                MetadataService.AsyncResult asyncResult = new MetadataService.AsyncResult();
                asyncResult.done = true;
                asyncResult.id = 'RetrieveId';
                response_x.result = asyncResult;
                response.put('response_x', response_x);
            }

            if (requestName == 'describeMetadata') {
                MetadataService.describeMetadataResponse_element describeMetadataResponseElement = new MetadataService.describeMetadataResponse_element();
                MetadataService.DescribeMetadataResult describeMetadataResult = new MetadataService.DescribeMetadataResult();
                List<MetadataService.DescribeMetadataObject> describeMetadataObjects = new List<MetadataService.DescribeMetadataObject>();

                MetadataService.DescribeMetadataObject describeMetadataObjectCustomObject = new MetadataService.DescribeMetadataObject();
                describeMetadataObjectCustomObject.xmlName = 'CustomObject';
                describeMetadataObjects.add(describeMetadataObjectCustomObject);

                MetadataService.DescribeMetadataObject describeMetadataObjectStandardValueSet = new MetadataService.DescribeMetadataObject();
                describeMetadataObjectStandardValueSet.xmlName = 'StandardValueSet';
                describeMetadataObjects.add(describeMetadataObjectStandardValueSet);

                MetadataService.DescribeMetadataObject describeMetadataObjectProfile = new MetadataService.DescribeMetadataObject();
                describeMetadataObjectProfile.xmlName = 'Profile';
                describeMetadataObjects.add(describeMetadataObjectProfile);

                describeMetadataResult.metadataObjects = describeMetadataObjects;
                describeMetadataResponseElement.result = describeMetadataResult;

                response.put('response_x', describeMetadataResponseElement);
            }

            if (requestName == 'checkRetrieveStatus') {
                System.debug('--- checkRetrieveStatus');
                if (isLimitError) {
                    System.debug('--- isLimitError');
                    MetadataService.checkRetrieveStatusResponse_element response_x = new MetadataService.checkRetrieveStatusResponse_element();
                    MetadataService.RetrieveResult asyncResult = new MetadataService.RetrieveResult();
                    asyncResult.done = true;
                    asyncResult.id = 'TestId';
                    asyncResult.errorMessage = 'LIMIT_EXCEEDED';
                    asyncResult.status = 'Succeeded';
                    asyncResult.zipFile = 'UEsDBBQAAAAAACer01AAAAAAAAAAAAAAAAAIACAAb2JqZWN0cy9VVA0ABwsD7V4MA+1eCwPtXnV4CwABBOgDAAAE6AMAAFBLAwQUAAgACACXgcJQAAAAAAAAAABvBQAAEwAgAG9iamVjdHMvVGVzdC5vYmplY3RVVA0AB05Q1l4FAu1eCwPtXnV4CwABBOgDAAAE6AMAANWUUUvDMBSF3/srSt9dqoiIZB1DGQyGymyfS5reurg0qbnp2Pz1ZqtrO9A9DBXtW05Ozr35aC4drUvpr8Cg0GoYnA/CwAfFdS7U8zBI4snZdTCKPHpbo9XlQ/YC3PruiMJhsLC2uiEENasGWGjDYcB1SS7C8IqEl6QEy3JmWRB5vvso30U8gbUuG+NNBdFMoKXkk43mBCiWSZgA5BgVTCJQ0pcaUyFA7heNUEt5z0qIxpwDYhrrJag05ZS0O50Z1haMYnKatxU6pbNJloH8CPR3gZQ0Wucx8FoLA21Qu+4s1jC+jA2oLd6971DsmbcgYtfO2ABzto4L6d/5GIDaLrQRCHmaIJjvYdBm+tvM/4BhqtAyxSFN5rOvGORQGeDMdn33lBNR7ev6ru4vcUqMPAnRHAoDuDj+Vn6C0Ufhv/amDv71N2bdcPTv3DwTEg+apCuBIhNS2E30WGdSOHI9yaOkPzgj7x1QSwcIPlU8wmYBAABvBQAAUEsBAhQDFAAAAAAAJ6vTUAAAAAAAAAAAAAAAAAgAIAAAAAAAAAAAAP1BAAAAAG9iamVjdHMvVVQNAAcLA+1eDAPtXgsD7V51eAsAAQToAwAABOgDAABQSwECFAMUAAgACACXgcJQPlU8wmYBAABvBQAAEwAgAAAAAAAAAAAAtIFGAAAAb2JqZWN0cy9UZXN0Lm9iamVjdFVUDQAHTlDWXgUC7V4LA+1edXgLAAEE6AMAAAToAwAAUEsFBgAAAAACAAIAtwAAAA0CAAAAAA==';
                    response_x.result = asyncResult;
                    response.put('response_x', response_x);
                } else if (isCalloutException) {
                    System.debug('--- isCalloutException');
                    throw new CalloutException('IO Exception: Exceeded max size limit of 12000000');
                } else if (!isDone) {
                    MetadataService.checkRetrieveStatusResponse_element response_x = new MetadataService.checkRetrieveStatusResponse_element();
                    MetadataService.RetrieveResult asyncResult = new MetadataService.RetrieveResult();
                    asyncResult.done = false;
                    asyncResult.id = 'TestId';
                    asyncResult.status = 'InProgress';
                    response_x.result = asyncResult;
                    response.put('response_x', response_x);
                } else {
                    MetadataService.checkRetrieveStatusResponse_element response_x = new MetadataService.checkRetrieveStatusResponse_element();
                    MetadataService.RetrieveResult asyncResult = new MetadataService.RetrieveResult();
                    asyncResult.done = true;
                    asyncResult.id = 'RetrieveId';
                    asyncResult.status = 'Succeeded';
                    asyncResult.zipFile = 'UEsDBBQAAAAAACer01AAAAAAAAAAAAAAAAAIACAAb2JqZWN0cy9VVA0ABwsD7V4MA+1eCwPtXnV4CwABBOgDAAAE6AMAAFBLAwQUAAgACACXgcJQAAAAAAAAAABvBQAAEwAgAG9iamVjdHMvVGVzdC5vYmplY3RVVA0AB05Q1l4FAu1eCwPtXnV4CwABBOgDAAAE6AMAANWUUUvDMBSF3/srSt9dqoiIZB1DGQyGymyfS5reurg0qbnp2Pz1ZqtrO9A9DBXtW05Ozr35aC4drUvpr8Cg0GoYnA/CwAfFdS7U8zBI4snZdTCKPHpbo9XlQ/YC3PruiMJhsLC2uiEENasGWGjDYcB1SS7C8IqEl6QEy3JmWRB5vvso30U8gbUuG+NNBdFMoKXkk43mBCiWSZgA5BgVTCJQ0pcaUyFA7heNUEt5z0qIxpwDYhrrJag05ZS0O50Z1haMYnKatxU6pbNJloH8CPR3gZQ0Wucx8FoLA21Qu+4s1jC+jA2oLd6971DsmbcgYtfO2ABzto4L6d/5GIDaLrQRCHmaIJjvYdBm+tvM/4BhqtAyxSFN5rOvGORQGeDMdn33lBNR7ev6ru4vcUqMPAnRHAoDuDj+Vn6C0Ufhv/amDv71N2bdcPTv3DwTEg+apCuBIhNS2E30WGdSOHI9yaOkPzgj7x1QSwcIPlU8wmYBAABvBQAAUEsBAhQDFAAAAAAAJ6vTUAAAAAAAAAAAAAAAAAgAIAAAAAAAAAAAAP1BAAAAAG9iamVjdHMvVVQNAAcLA+1eDAPtXgsD7V51eAsAAQToAwAABOgDAABQSwECFAMUAAgACACXgcJQPlU8wmYBAABvBQAAEwAgAAAAAAAAAAAAtIFGAAAAb2JqZWN0cy9UZXN0Lm9iamVjdFVUDQAHTlDWXgUC7V4LA+1edXgLAAEE6AMAAAToAwAAUEsFBgAAAAACAAIAtwAAAA0CAAAAAA==';
                    response_x.result = asyncResult;
                    response.put('response_x', response_x);
                }
            }
        }
    }

    //if you not found necessary key => value, please write below it
    public static final Map<String, String> typeFolderMap = new Map<String, String>{
        'ApexClass' => 'classes',
        'Document' => 'DocumentFolder',
        'QuickAction' => 'quickActions'
    };

    //if you not found necessary key => value, please write below it
    public static final Map<String, String> typeSuffixMap = new Map<String, String>{
        'ApexClass' => 'cls',
        'Document' => 'png', // can be something else
        'QuickAction' => 'quickAction'
    };
}