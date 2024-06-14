public with sharing class TrackingAutomationScheduler implements Schedulable {
    public Map<Id, Id> failedAsyncJobIdToTrackingSettingIdToMap;

    public TrackingAutomationScheduler() {
    }

    public TrackingAutomationScheduler(Map<Id, Id> failedAsyncJobIdToTrackingSettingIdToMap) {
        this.failedAsyncJobIdToTrackingSettingIdToMap = failedAsyncJobIdToTrackingSettingIdToMap;
    }

    public void execute(SchedulableContext context) {
        deleteSettingWithoutOrg();

        if (failedAsyncJobIdToTrackingSettingIdToMap != null) {
            solveStackProcess(failedAsyncJobIdToTrackingSettingIdToMap);
            failedAsyncJobIdToTrackingSettingIdToMap.clear();
        }

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Is_Enabled__c.getDescribe(),
                    Tracking_Setting__c.Current_Apex_Job_Id__c.getDescribe(),
                    Tracking_Setting__c.Last_Start_Retrieval__c.getDescribe(),
                    Tracking_Setting__c.Is_Processed__c.getDescribe()
                }
            }
        );

        Map<Id, Tracking_Setting__c> trackingSettingMap = new Map<Id, Tracking_Setting__c>(
            [
                SELECT Id, Last_Start_Retrieval__c, Current_Apex_Job_Id__c, Is_Processed__c, Metadata_Types__c
                FROM Tracking_Setting__c
                ORDER BY Last_Start_Retrieval__c DESC
            ]
        );

        Boolean isExternalTracking = TrackingService.isExternalRetrievalEnabled();
        Set<Id> trackingSettingIdsToProcessInAgent = new Set<Id>();

        Map<Id, Id> currentFailedAsyncJobIdToTrackingSettingIdToMap = checkIsProcessStack(trackingSettingMap.values());

        Datetime nextDatetime = Datetime.now();
        Tracking_Setting__c nextRetrieveTrackingSetting = null;

        for (Tracking_Setting__c trackingSetting : trackingSettingMap.values()) {
            if (String.isBlank(trackingSetting.Metadata_Types__c)) {
                trackingSetting.Is_Enabled__c = false;

                DatabaseUtils.updateRecord(
                    trackingSetting,
                    new List<Schema.DescribeFieldResult>{ Tracking_Setting__c.Is_Enabled__c.getDescribe() }
                );

                continue;
            }

            if (trackingSetting.Is_Processed__c && !isExternalTracking) {
                reschedule(context.getTriggerId(), currentFailedAsyncJobIdToTrackingSettingIdToMap);
                return;
            }

            if (trackingSetting.Is_Processed__c && isExternalTracking) {
                continue;
            }

            Datetime organizationNextDatetime = trackingSetting.Last_Start_Retrieval__c != null
                ? trackingSetting.Last_Start_Retrieval__c
                : Datetime.now().addYears(-1);

            if (!isExternalTracking && nextDatetime > organizationNextDatetime && !trackingSetting.Is_Processed__c) {
                nextDatetime = organizationNextDatetime;
                nextRetrieveTrackingSetting = trackingSetting;
            }

            if (isExternalTracking && nextDatetime > organizationNextDatetime && !trackingSetting.Is_Processed__c) {
                trackingSettingIdsToProcessInAgent.add(trackingSetting.Id);
            }
        }

        if (!trackingSettingIdsToProcessInAgent.isEmpty() && isExternalTracking) {
            Database.executeBatch(new TrackingAgentJobHandlerBatch(trackingSettingIdsToProcessInAgent), 1);
        }

        if (nextRetrieveTrackingSetting != null) {
            TrackingService.Logger logger = TrackingService.createLogger(nextRetrieveTrackingSetting.Id);

            nextRetrieveTrackingSetting.Is_Processed__c = true;
            nextRetrieveTrackingSetting.Last_Start_Retrieval__c = Datetime.now();

            DatabaseUtils.upsertRecord(
                nextRetrieveTrackingSetting,
                new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Last_Start_Retrieval__c.getDescribe()
                }
            );

            String jobId = Database.executeBatch(
                new TrackingRequestRetrieveBatch(nextRetrieveTrackingSetting.Id, logger),
                1
            );

            TrackingService.setApexJobIdSetting(nextRetrieveTrackingSetting.Id, jobId);
        }

        reschedule(context.getTriggerId(), currentFailedAsyncJobIdToTrackingSettingIdToMap);
    }

    public static void schedule() {
        schedule(null);
    }

    public static void schedule(Map<Id, Id> failedAsyncJobIdToTrackingSettingIdToMap) {
        Datetime dt = Datetime.now().addMinutes(2);
        String scheduleExpression = String.format(
            '{0} {1} {2} {3} {4} ? {5}',
            new List<Integer>{ dt.second(), dt.minute(), dt.hour(), dt.day(), dt.month(), dt.year() }
        );
        TrackingAutomationScheduler trackingAutomationScheduler;
        if (failedAsyncJobIdToTrackingSettingIdToMap == null) {
            trackingAutomationScheduler = new TrackingAutomationScheduler();
        } else {
            trackingAutomationScheduler = new TrackingAutomationScheduler(failedAsyncJobIdToTrackingSettingIdToMap);
        }

        if (!Test.isRunningTest()) {
            System.schedule(TrackingService.TRACKING_SCHEDULER_NAME, scheduleExpression, trackingAutomationScheduler);
        }
    }
    public static void reschedule(String jobId, Map<Id, Id> failedAsyncJobIdToTrackingSettingIdToMap) {
        System.abortJob(jobId);
        schedule(failedAsyncJobIdToTrackingSettingIdToMap);
    }

    public static void reschedule(String jobId) {
        reschedule(jobId, null);
    }

    public static Map<Id, Id> checkIsProcessStack(List<Tracking_Setting__c> trackingSettingList) {
        Map<Id, Id> asyncJobIdToTrackingSettingIdMap = new Map<Id, Id>();
        for (Tracking_Setting__c trackingSetting : trackingSettingList) {
            if (trackingSetting.Is_Processed__c && String.isNotBlank(trackingSetting.Current_Apex_Job_Id__c)) {
                asyncJobIdToTrackingSettingIdMap.put(trackingSetting.Current_Apex_Job_Id__c, trackingSetting.Id);
            }
        }

        List<Id> asyncJobIdList = new List<Id>();
        List<Id> cronTriggerIdList = new List<Id>();
        for (Id jobId : asyncJobIdToTrackingSettingIdMap.keySet()) {
            String jobType = String.valueOf(jobId.getSobjectType());
            if (jobType == 'CronTrigger') {
                cronTriggerIdList.add(jobId);
            } else if (jobType == 'AsyncApexJob') {
                asyncJobIdList.add(jobId);
            }
        }

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                AsyncApexJob.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    AsyncApexJob.CronTriggerId.getDescribe()
                }
            }
        );

        List<AsyncApexJob> failedAsyncApexJobList = [
            SELECT Id, CronTriggerId
            FROM AsyncApexJob
            WHERE Status = 'Failed' AND (Id IN :asyncJobIdList OR CronTriggerId IN :cronTriggerIdList)
        ];

        Map<Id, Id> failedAsyncJobIdToTrackingSettingIdToMap = new Map<Id, Id>();
        for (AsyncApexJob apexJob : failedAsyncApexJobList) {
            if (
                String.isNotBlank(apexJob.CronTriggerId) &&
                asyncJobIdToTrackingSettingIdMap.containsKey(apexJob.CronTriggerId)
            ) {
                failedAsyncJobIdToTrackingSettingIdToMap.put(
                    apexJob.Id,
                    asyncJobIdToTrackingSettingIdMap.get(asyncJobIdToTrackingSettingIdMap.get(apexJob.CronTriggerId))
                );
            } else if (asyncJobIdToTrackingSettingIdMap.containsKey(apexJob.Id)) {
                failedAsyncJobIdToTrackingSettingIdToMap.put(
                    apexJob.Id,
                    asyncJobIdToTrackingSettingIdMap.get(apexJob.Id)
                );
            }
        }

        return failedAsyncJobIdToTrackingSettingIdToMap;
    }

    public static void solveStackProcess(Map<Id, Id> failedAsyncJobIdToTrackingSettingIdToMap) {
        Map<Id, Id> trackingSettingIdToFailedAsyncJobIdToMap = new Map<Id, Id>();
        for (String failedAsyncJobId : failedAsyncJobIdToTrackingSettingIdToMap.keySet()) {
            trackingSettingIdToFailedAsyncJobIdToMap.put(
                failedAsyncJobIdToTrackingSettingIdToMap.get(failedAsyncJobId),
                failedAsyncJobId
            );
        }

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Is_Enabled__c.getDescribe(),
                    Tracking_Setting__c.Current_Apex_Job_Id__c.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingSettingToUpdateList = new List<Tracking_Setting__c>();
        for (Tracking_Setting__c trackingSetting : [
            SELECT Id, Is_Processed__c, Is_Enabled__c, Current_Apex_Job_Id__c
            FROM Tracking_Setting__c
            WHERE Id IN :failedAsyncJobIdToTrackingSettingIdToMap.values()
        ]) {
            if (
                trackingSettingIdToFailedAsyncJobIdToMap.containsKey(trackingSetting.Id) &&
                trackingSetting.Is_Enabled__c &&
                trackingSetting.Is_Processed__c &&
                trackingSetting.Current_Apex_Job_Id__c != null &&
                trackingSetting.Current_Apex_Job_Id__c ==
                trackingSettingIdToFailedAsyncJobIdToMap.get(trackingSetting.Id)
            ) {
                trackingSetting.Is_Processed__c = false;
                trackingSetting.Current_Apex_Job_Id__c = null;
                trackingSetting.Current_Jobs__c = null;
                trackingSettingToUpdateList.add(trackingSetting);
            }
        }

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Metadata_Log__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Completed_Date__c.getDescribe(),
                    Metadata_Log__c.Job_Completed__c.getDescribe(),
                    Metadata_Log__c.Tracking_Setting__c.getDescribe()
                }
            }
        );

        List<Metadata_Log__c> metadataLogToUpdateList = new List<Metadata_Log__c>();
        for (Metadata_Log__c metadataLog : [
            SELECT Id, Completed_Date__c, Job_Completed__c, Tracking_Setting__c
            FROM Metadata_Log__c
            WHERE Tracking_Setting__c IN :trackingSettingToUpdateList
            ORDER BY CreatedDate DESC
            LIMIT :trackingSettingToUpdateList.size()
        ]) {
            if (metadataLog.Completed_Date__c == null && !metadataLog.Job_Completed__c) {
                metadataLog.Job_Completed__c = true;
                metadataLog.Completed_Date__c = Datetime.now();
                metadataLog.Status__c = 'Error';
                metadataLogToUpdateList.add(metadataLog);
            }
        }

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                AsyncApexJob.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    AsyncApexJob.ExtendedStatus.getDescribe()
                }
            }
        );

        Map<Id, AsyncApexJob> failedAsyncApexJobMap = new Map<Id, AsyncApexJob>(
            [
                SELECT Id, ExtendedStatus
                FROM AsyncApexJob
                WHERE
                    Status = 'Failed'
                    AND Id IN :failedAsyncJobIdToTrackingSettingIdToMap.keySet()
                    AND ExtendedStatus != NULL
            ]
        );

        List<Attachment> attachmentList = new List<Attachment>();
        for (Metadata_Log__c metadataLog : metadataLogToUpdateList) {
            if (
                trackingSettingIdToFailedAsyncJobIdToMap.containsKey(metadataLog.Tracking_Setting__c) &&
                failedAsyncApexJobMap.containsKey(
                    trackingSettingIdToFailedAsyncJobIdToMap.get(metadataLog.Tracking_Setting__c)
                )
            ) {
                TrackingService.Logger logger = new TrackingService.Logger(
                    metadataLog.Id,
                    TrackingService.TRACKING_ORGANIZATION_LOG_NAME
                );
                logger.addLine(
                    failedAsyncApexJobMap.get(
                            trackingSettingIdToFailedAsyncJobIdToMap.get(metadataLog.Tracking_Setting__c)
                        )
                        .ExtendedStatus
                );
                Attachment attachment = logger.updateLog(false);
                if (attachment != null) {
                    attachmentList.add(attachment);
                }
            }
        }

        DatabaseUtils.upsertRecords(
            attachmentList,
            new List<Schema.DescribeFieldResult>{ Attachment.Name.getDescribe(), Attachment.Body.getDescribe() }
        );

        DatabaseUtils.upsertRecords(
            metadataLogToUpdateList,
            new List<Schema.DescribeFieldResult>{
                Metadata_Log__c.Job_Completed__c.getDescribe(),
                Metadata_Log__c.Status__c.getDescribe(),
                Metadata_Log__c.Completed_Date__c.getDescribe()
            }
        );

        DatabaseUtils.upsertRecords(
            trackingSettingToUpdateList,
            new List<Schema.DescribeFieldResult>{
                Tracking_Setting__c.Is_Processed__c.getDescribe(),
                Tracking_Setting__c.Current_Apex_Job_Id__c.getDescribe()
            }
        );
    }

    public static void abortOldSchedulers() {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                CronTrigger.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
            }
        );

        for (CronTrigger cronTrigger : [
            SELECT Id
            FROM CronTrigger
            WHERE
                (CronJobDetail.Name LIKE :TrackingService.TRACKING_SCHEDULER_NAME + '%'
                AND CronJobDetail.Name != :TrackingService.TRACKING_SCHEDULER_NAME
                AND State != 'EXECUTING')
                OR (CronJobDetail.Name LIKE :TrackingService.TRACKING_SCHEDULER_NAME + '%'
                AND State = 'DELETED')
        ]) {
            System.abortJob(cronTrigger.Id);
        }
    }

    public static void deleteSettingWithoutOrg() {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
            }
        );

        List<Tracking_Setting__c> trackingSettingList = [
            SELECT Id
            FROM Tracking_Setting__c
            WHERE Organization__c = NULL
        ];

        DatabaseUtils.deleteRecords(trackingSettingList);
    }
}