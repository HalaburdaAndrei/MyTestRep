@isTest
public with sharing class TrackingAgentJobHandlerBatchTest {
    public static final String HTTP_START_JOB_RESPONSE = '{"jobId": "testJobId"}';

    @IsTest
    public static void standardLaunching() {
        Test.setMock(WebServiceMock.class, new MetadataUtils.WebServiceMockImpl());

        Organisation__c org = new Organisation__c(Name = 'Test Org', Username__c = 'test@testOrg.com');
        insert org;

        Authorization_Details__c auth = new Authorization_Details__c(
            AuthorisedUser__c = 'test@testOrg.com',
            Name = 'test@testOrg.com',
            AccessToken__c = 'test',
            RefreshToken__c = 'test',
            InstanceURL__c = 'test',
            Is_Primary_Org__c = true
        );
        insert auth;

        Tracking_Setting__c trackingOrganizationSetting = new Tracking_Setting__c();
        trackingOrganizationSetting.Organization__c = org.Id;
        trackingOrganizationSetting.Is_Processed__c = false;
        trackingOrganizationSetting.Is_Enabled__c = true;
        trackingOrganizationSetting.Last_Start_Retrieval__c = Datetime.now().addDays(-1);
        trackingOrganizationSetting.Metadata_Types__c = 'ApexClass';
        insert trackingOrganizationSetting;

        Credentials__c credentials = new Credentials__c();
        credentials.Pipeline_Agent_URL__c = 'test-agent.com';
        credentials.Retrieval_Method__c = ExternalSnapshotService.ExternalRetrievalMethod;
        insert credentials;

        Test.setMock(
            HttpCalloutMock.class,
            new HttpCalloutMockImpl(
                new Map<String, String>{ TrackingService.ExternalJobURL => HTTP_START_JOB_RESPONSE },
                201
            )
        );

        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator'];

        User testUser = new User(
            Alias = 'standt',
            Email = 'standarduser@testorg.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'User 1',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'adminsassawddcawddsxca@testorg.com'
        );
        insert testUser;

        Set<Id> trackingSettingIds = new Set<Id>{ trackingOrganizationSetting.Id };
        Test.startTest();
        Database.executeBatch(new TrackingAgentJobHandlerBatch(trackingSettingIds), 1);
        Test.stopTest();

        System.assertEquals(false, [SELECT Id, Is_Processed__c FROM Tracking_Setting__c LIMIT 1].Is_Processed__c);
    }
}