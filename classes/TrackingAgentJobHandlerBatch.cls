public with sharing class TrackingAgentJobHandlerBatch implements Database.Batchable<sObject>, Database.AllowsCallouts, Database.Stateful {    
    private Set<Id> trackingSettingIdsToProcess = new Set<Id>();

    public TrackingAgentJobHandlerBatch(Set<Id> trackingSettingIdsToProcess) {
        this.trackingSettingIdsToProcess = trackingSettingIdsToProcess;
    }

    public  Database.QueryLocator start(Database.BatchableContext batchableContext) {
        return Database.getQueryLocator('SELECT Id, Last_Start_Retrieval__c, Is_Processed__c, Metadata_Types__c, Organization__c ' +
            'FROM Tracking_Setting__c WHERE Id IN :trackingSettingIdsToProcess');
    }

    public void execute(Database.BatchableContext batchableContext, List<Tracking_Setting__c> trackingSettingList) {
        Tracking_Setting__c trackingSetting = trackingSettingList[0];
        try {
            AuthUtils.AuthenticateDetails authDetails = AuthUtils.authenticateAnOrg(trackingSetting.Organization__c);

            if(!authDetails.isSuccess && !Test.isRunningTest()) {
                return;
            }
    
            Datetime lastStartRetrieveDate = trackingSetting.Last_Start_Retrieval__c != null ? trackingSetting.Last_Start_Retrieval__c : Datetime.now().addYears(-1);
            TrackingService.StartJobRequestWrapper runJobBody = new TrackingService.StartJobRequestWrapper(
                lastStartRetrieveDate,
                trackingSetting.Organization__c,
                trackingSetting.Id,
                trackingSetting.Metadata_Types__c,
                UserInfo.getTimeZone().getID()
            );
            runJobBody.targetOrgCredentials.accessToken = authDetails.details.AccessToken__c;
            runJobBody.targetOrgCredentials.instanceUrl = authDetails.details.InstanceURL__c;
            runJobBody.targetOrgCredentials.refreshToken = authDetails.details.RefreshToken__c;
            runJobBody.flosumOrgCredentials.accessToken =  UserInfo.getSessionId();
            runJobBody.flosumOrgCredentials.instanceUrl = Url.getSalesforceBaseUrl().toExternalForm();

            String jobId = TrackingService.startAgentJob(JSON.serialize(runJobBody));

        } catch (Exception e) {
            TrackingService.Logger logger = TrackingService.createLogger(trackingSetting.Id);
            TrackingService.handleError(trackingSetting.Id, logger, 'Start External Job Error: ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext batchableContext) {
    }
}