public with sharing class CreateMultiMetaSnapshotController {
    public Organisation__c orgRec { get; private set; }
    public Integer lastModifiedInDays { get; set; }
    public String customLookupPageName { get; private set; }
    public String metadataTypeStr { get; private set; }
    public String jsMetadataTypeStr { get; private set; }
    public String manageMetadataTypeToRetrieve { get; private set; }
    public AuthUtils.AuthenticateDetails authDetails { get; private set; }
    public String snapshotId { get; set; }
    public Integer localApiVersion { get; private set; }
    public boolean IsApexCompleted { get; set; }
    public boolean isDisplayOmniStudioRetrieveCheckbox { get; private set; }

    public transient String metadataTypesForBatch { get; set; }
    public transient String filterJSON { get; set; }
    public transient Integer noOfDays { get; set; }
    public transient String noOfHours { get; set; }

    public String defaultFilterJSON { get; set; }
    public List<SelectOption> nameSpaceAvailableList { get; set; }
    public List<SelectOption> nameSpaceSelectedList { get; set; }
    public String snapName { get; set; }

    public String namespacePrefix { get; set; }

    //Veeva
    public Boolean isVeevaOrg { get; set; }

    public CreateMultiMetaSnapshotController(ApexPages.StandardController controller) {
        manageMetadataTypeToRetrieve = '';
        String tempsnapName = ApexPages.currentPage().getParameters().get('snapName');
        if (tempsnapName != null) {
            snapName = tempsnapName;
        }
        nameSpaceAvailableList = new List<SelectOption>();
        nameSpaceSelectedList = new List<SelectOption>();

        namespacePrefix = FlosumConstants.getNameSpacePrefix();

        localApiVersion = FlosumConstants.apiversion;
        lastModifiedInDays = 14;
        orgRec = (Organisation__c) controller.getRecord();

        if (orgRec != null && orgRec.Id != null) {
            String snapId = ApexPages.currentPage().getParameters().get('snapId');
            List<Snapshot__c> snapLi = new List<Snapshot__c>();
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Snapshot__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Snapshot__c.Organisation__c.getDescribe(),
                        Snapshot__c.Filter__c.getDescribe(),
                        Snapshot__c.Last_Modified_In_Days__c.getDescribe()
                    }
                }
            );
            snapLi = [
                SELECT Id, Organisation__c, Filter__c, Last_Modified_In_Days__c
                FROM Snapshot__c
                WHERE Id = :snapId
                LIMIT 1
            ];
            if (snapLi.size() == 1 && snapLi[0].Filter__c != null && snapLi[0].Filter__c != '') {
                defaultFilterJSON = EncodingUtil.urlDecode(snapLi[0].Filter__c, 'UTF-8');
                lastModifiedInDays = (Integer) snapLi[0].Last_Modified_In_Days__c;
            }
            customLookupPageName = Page.CustomLookup.getUrl() + '?orgId=' + orgRec.Id + '&';
            isVeevaOrg = VeevaService.checkVeevaOrg(orgRec.Id);
            authDetails = AuthUtils.authenticateAnOrg(orgRec.Id, FlosumConstants.DEVELOPER);
            if (authDetails.isSuccess) {
                ApexPages.addMessage(
                    new ApexPages.Message(ApexPages.Severity.INFO, FlosumConstants.SNAPSHOT_PERFORMANCE_TIP_3)
                );
                ApexPages.addMessage(
                    new ApexPages.Message(ApexPages.Severity.INFO, FlosumConstants.SNAPSHOT_PERFORMANCE_TIP_2)
                );
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, authDetails.infoMessage));
                listNameSpacePrefix();
            } else if (!isVeevaOrg) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, authDetails.errorMessage));
            }

            listMetadaTypes();
            isDisplayOmniStudioRetrieveCheckbox = Post_Install_Steps__c.getOrgDefaults().Retrieve_Active_Omnistudio_in_Snapshot__c;
        }
    }

    public void listNameSpacePrefix() {
        manageMetadataTypeToRetrieve = '';
        try {
            Set<String> tempNameSpaceSet = new Set<String>();
            if (defaultFilterJSON != null && defaultFilterJSON != '') {
                FlosumUtils.ReCreateSnapshotFilterWraper reCreateFilterInfo = (FlosumUtils.ReCreateSnapshotFilterWraper) JSON.deserialize(
                    defaultFilterJSON,
                    FlosumUtils.ReCreateSnapshotFilterWraper.class
                );
                tempNameSpaceSet = reCreateFilterInfo.snapShotFilter.selectedNamespaceSet;
            } else {
                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        Namespace_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            Namespace_Setting__c.Namespace_Prifix__c.getDescribe(),
                            Namespace_Setting__c.Is_Selected__c.getDescribe()
                        }
                    }
                );
                for (Namespace_Setting__c nameSpace : [
                    SELECT Id, Namespace_Prifix__c, Is_Selected__c
                    FROM Namespace_Setting__c
                    WHERE Is_Selected__c = TRUE
                ]) {
                    tempNameSpaceSet.add(nameSpace.Namespace_Prifix__c);
                }
            }
            MetadataService.MetadataPort service = MetadataUtils.createService(
                authDetails.details.AccessToken__c,
                authDetails.details.InstanceURL__c
            );

            List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery>();
            MetadataService.ListMetadataQuery queryLayout = new MetadataService.ListMetadataQuery();
            queryLayout.type_x = 'InstalledPackage';
            queries.add(queryLayout);
            MetadataService.FileProperties[] fileProperties = new List<MetadataService.FileProperties>();
            if (Test.isRunningTest()) {
                fileProperties = MetadataUtils.testListMetadata();
            } else {
                // query metadata items by callout
                fileProperties = service.listMetadata(queries, FlosumConstants.apiversion);
            }
            if (fileProperties != null) {
                Set<String> nameSpaceSet = new Set<String>();
                for (MetadataService.FileProperties fileProperty : fileProperties) {
                    nameSpaceSet.add(fileProperty.namespacePrefix);
                }
                for (String tempStr : nameSpaceSet) {
                    if (tempNameSpaceSet.contains(tempStr)) {
                        nameSpaceSelectedList.add(new SelectOption(tempStr, tempStr));
                    } else {
                        nameSpaceAvailableList.add(new SelectOption(tempStr, tempStr));
                    }
                }
            }
            manageMetadataTypeToRetrieve = JSON.serialize(FlosumConstants.manageMetadataTypeToRetrieve);
        } catch (Exception ex) {
            //System.abortJob(info.getJobId());
        }
    }

    public void listMetadaTypes() {
        metadataTypeStr = '';
        jsMetadataTypeStr = '';
        try {
            List<FlosumSecurity.ObjectAuthorized> objList = new List<FlosumSecurity.ObjectAuthorized>();
            objList.add(new FlosumSecurity.ObjectAuthorized(FlosumSecurity.isUpdate, Schema.SObjectType.Snapshot__c));
            objList.add(new FlosumSecurity.ObjectAuthorized(FlosumSecurity.isCreate, Schema.SObjectType.Snapshot__c));
            objList.add(
                new FlosumSecurity.ObjectAuthorized(FlosumSecurity.isUpdate, Schema.SObjectType.Metadata_Log__c)
            );
            objList.add(
                new FlosumSecurity.ObjectAuthorized(FlosumSecurity.isCreate, Schema.SObjectType.Metadata_Log__c)
            );
            objList.add(new FlosumSecurity.ObjectAuthorized(FlosumSecurity.isUpdate, Schema.SObjectType.Temp_Log__c));
            objList.add(new FlosumSecurity.ObjectAuthorized(FlosumSecurity.isCreate, Schema.SObjectType.Temp_Log__c));
            objList.add(new FlosumSecurity.ObjectAuthorized(FlosumSecurity.isDelete, Schema.SObjectType.Temp_Log__c));
            objList.add(
                new FlosumSecurity.ObjectAuthorized(FlosumSecurity.isCreate, Schema.SObjectType.Metadata_Item__c)
            );
            objList.add(
                new FlosumSecurity.ObjectAuthorized(FlosumSecurity.isUpdate, Schema.SObjectType.Metadata_Item__c)
            );

            List<FlosumSecurity.FieldAuthorized> fieldList = new List<FlosumSecurity.FieldAuthorized>();

            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Item__c.fields.Snapshot__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Item__c.fields.API_Name__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Item__c.fields.Name__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Item__c.fields.Label__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Item__c.fields.Last_Modified_Date__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Item__c.fields.Folder__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Item__c.fields.Is_Retrieved__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Item__c.fields.Last_Updated_By__c
                )
            );

            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Snapshot__c.fields.Apex_Is_Completed__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Snapshot__c.fields.Is_Error__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Log__c.fields.Process_Type__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Log__c.fields.Batch_Job_Id__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Log__c.fields.Metadata_Types__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Log__c.fields.Snapshot__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Log__c.fields.Process_Log__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Log__c.fields.Succeed__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Log__c.fields.Job_Completed__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isCreate,
                    Schema.SObjectType.Metadata_Log__c.fields.Status__c
                )
            );

            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Metadata_Log__c.fields.Process_Type__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Metadata_Log__c.fields.Batch_Job_Id__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Metadata_Log__c.fields.Metadata_Types__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Metadata_Log__c.fields.Snapshot__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Metadata_Log__c.fields.Process_Log__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Metadata_Log__c.fields.Succeed__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Metadata_Log__c.fields.Job_Completed__c
                )
            );
            fieldList.add(
                new FlosumSecurity.FieldAuthorized(
                    FlosumSecurity.isUpdate,
                    Schema.SObjectType.Metadata_Log__c.fields.Status__c
                )
            );

            boolean fieldAccess = FlosumSecurity.isAuthorized(fieldList);
            boolean objAccess = FlosumSecurity.isObjAuthorized(objList);

            if (fieldAccess && objAccess) {
                if (authDetails != null && authDetails.details != null && authDetails.isSuccess) {
                    List<Authorization_Details__c> detail = [
                        SELECT Id, AccessToken__c, InstanceURL__c
                        FROM Authorization_Details__c
                        WHERE Id = :authDetails.details.Id
                        LIMIT 1
                    ];
                    if (authDetails.details != null) {
                        List<String> metadataTypeLi = new List<String>();
                        Set<String> supportedMetadataTypes = FlosumConstants.getAllMetadataTypes();
                        MetadataService.MetadataPort service = MetadataUtils.createService(
                            authDetails.details.AccessToken__c,
                            authDetails.details.InstanceURL__c
                        );
                        MetadataService.DescribeMetadataResult describeResult = service.describeMetadata(
                            FlosumConstants.apiversion
                        );
                        for (MetadataService.DescribeMetadataObject metadataObject : describeResult.metadataObjects) {
                            if (supportedMetadataTypes.contains(metadataObject.xmlName))
                                metadataTypeLi.add(metadataObject.xmlName);
                            if (metadataObject.childXmlNames != null)
                                for (String childXmlName : metadataObject.childXmlNames)
                                    if (childXmlName != null)
                                        if (supportedMetadataTypes.contains(childXmlName))
                                            metadataTypeLi.add(childXmlName);
                        }
                        metadataTypeLi.addAll(FlosumConstants.snapshotTypesNotSupportedByDescribeSet);
                        metadataTypeLi.sort();
                        Set<String> jsMap = new Set<String>();
                        for (Retrieval_By_JS_Type__mdt jsType : [
                            SELECT Id, DeveloperName
                            FROM Retrieval_By_JS_Type__mdt
                            LIMIT 49999
                        ]) {
                            jsMap.add(jsType.DeveloperName);
                        }
                        for (String metaType : metadataTypeLi) {
                            if (metadataTypeStr == '')
                                metadataTypeStr += metaType;
                            else
                                metadataTypeStr += ',' + metaType;

                            if (jsMap.contains(metaType)) {
                                if (jsMetadataTypeStr == '')
                                    jsMetadataTypeStr += metaType;
                                else
                                    jsMetadataTypeStr += ',' + metaType;
                            }
                        }
                    }
                }
            } else {
                ApexPages.addMessage(
                    new ApexPages.Message(ApexPages.Severity.Error, 'Object or field permissions are missing.')
                );
            }
        } catch (Exception ex) {
            if (ex.getMessage().contains(' INVALID_OPERATION_WITH_EXPIRED_PASSWORD'))
                ApexPages.addMessage(
                    new ApexPages.Message(ApexPages.Severity.Error, 'Oraganisation password has been expired.')
                );
            else
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, ex.getMessage()));
        }
    }

    public void snapshotAction() {
        if (authDetails != null && authDetails.details != null && authDetails.needToUpdateDetails) {
            /*DatabaseUtils.updateCustomSettingRecord(
                    authDetails.details,
                    new List<Schema.DescribeFieldResult>{
                        Authorization_Details__c.AccessToken__c.getDescribe(),
                        Authorization_Details__c.RefreshToken__c.getDescribe()
                    }
            );*/
            update authDetails.details;
        }
    }

    public PageReference redirectToSnapshot() {
        FlosumUtils.runMaintenanceScheduler();
        AnalyticsService.runAnalyticsScheduler();

        System.debug('filterJSON---' + filterJSON);
        System.debug(IsApexCompleted);
        List<Metadata_Log__c> logLi = new List<Metadata_Log__c>();
        if (IsApexCompleted) {
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Metadata_Log__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Metadata_Log__c.Process_Type__c.getDescribe(),
                        Metadata_Log__c.Job_Completed__c.getDescribe(),
                        Metadata_Log__c.Status__c.getDescribe(),
                        Metadata_Log__c.Succeed__c.getDescribe(),
                        Metadata_Log__c.Snapshot__c.getDescribe()
                    }
                }
            );
            List<Metadata_Log__c> logList = [
                SELECT Id, Process_Type__c, Job_Completed__c, Status__c, Succeed__c
                FROM Metadata_Log__c
                WHERE Snapshot__c = :snapshotId AND Process_Type__c = :FlosumConstants.PROCESS_SNAPSHOT_LOG_APEX
                LIMIT 1
                FOR UPDATE
            ];
            if (logList != null && logList.size() > 0) {
                logList[0].Job_Completed__c = true;
                logList[0].Status__c = FlosumConstants.STATUS_COMPLETED;
                logList[0].Succeed__c = true;
                logLi.add(logList[0]);
            }
        }
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Metadata_Log__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Process_Type__c.getDescribe(),
                    Metadata_Log__c.Job_Completed__c.getDescribe(),
                    Metadata_Log__c.Status__c.getDescribe(),
                    Metadata_Log__c.Succeed__c.getDescribe(),
                    Metadata_Log__c.Snapshot__c.getDescribe()
                }
            }
        );
        List<Metadata_Log__c> logList = [
            SELECT Id, Process_Type__c, Job_Completed__c, Status__c, Succeed__c
            FROM Metadata_Log__c
            WHERE Snapshot__c = :snapshotId AND Process_Type__c = :FlosumConstants.PROCESS_SNAPSHOT_LOG_JS
            LIMIT 1
            FOR UPDATE
        ];
        if (logList != null && logList.size() > 0) {
            logList[0].Job_Completed__c = true;
            logList[0].Status__c = FlosumConstants.STATUS_COMPLETED;
            logList[0].Succeed__c = true;
            logLi.add(logList[0]);
        }
        System.debug('logLi.size()--' + logLi.size());
        if (logLi.size() > 0) {
            DatabaseUtils.updateRecords(
                logLi,
                new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Job_Completed__c.getDescribe(),
                    Metadata_Log__c.Status__c.getDescribe(),
                    Metadata_Log__c.Succeed__c.getDescribe()
                }
            );

            System.debug('After update');
        }

        Credentials__c creds = Credentials__c.getOrgDefaults();
        if (creds != null && creds.Id != null) {
            List<Authorization_Details__c> detail = [
                SELECT Id, AccessToken__c, InstanceURL__c
                FROM Authorization_Details__c
                WHERE Id = :authDetails.details.Id
                LIMIT 1
            ];
            if (detail != null && detail.size() > 0 && metadataTypesForBatch != null && metadataTypesForBatch != '') {
                List<String> apexmetaTypeList = (List<String>) JSON.deserialize(
                    metadataTypesForBatch,
                    List<String>.class
                );
                Set<String> noOfHoursSet = new Set<String>{ '1', '3', '6', '12' };
                DateTime tempDt = System.now();
                System.debug('noOfDays----' + noOfDays);
                System.debug('tempDt------' + tempDt);
                System.debug('noOfHours----' + noOfHours);
                if (noOfDays != null && (noOfDays != 0 || (noOfDays == 0 && noOfHoursSet.contains(noOfHours)))) {
                    tempDt = tempDt.addDays(-noOfDays);
                    System.debug('noOfHours----' + noOfHours);
                    if (noOfHoursSet.contains(noOfHours)) {
                        tempDt = tempDt.addHours(-(Integer.valueOf(noOfHours)));
                    }
                    System.debug('tempDt------' + tempDt);
                    //Database.executeBatch(new ComponentQueryBatch(apexmetaTypeList, detail[0].AccessToken__c, detail[0].InstanceURL__c, snapshotId, tempDt),1);
                    FlosumUtils.SnapshotFilterInfo tempFilterInfo = (FlosumUtils.SnapshotFilterInfo) JSON.deserialize(
                    	filterJSON,
                        FlosumUtils.SnapshotFilterInfo.class
                    );
                    tempFilterInfo.selectedNamespaceSet = new Set<String>();
                    if (nameSpaceSelectedList.size() > 0) {
                        for (SelectOption se : nameSpaceSelectedList) {
                            tempFilterInfo.selectedNamespaceSet.add(se.getValue());
                        }
                        tempFilterInfo.isNameSpaceSelected = true;
                    }

                    if (!IsApexCompleted) {
                        Database.executeBatch(
                            new ComponentQueryBatch(
                                apexmetaTypeList,
                                detail[0].AccessToken__c,
                                detail[0].InstanceURL__c,
                                snapshotId,
                                tempDt,
                                JSON.serialize(tempFilterInfo)
                            ),
                            1
                        );
                    }

                    FlosumUtils.ReCreateSnapshotFilterWraper reCreateSnapshot = new FlosumUtils.ReCreateSnapshotFilterWraper(
                    	apexmetaTypeList,
                        tempDt,
                        tempFilterInfo
                    );
                    reCreateSnapshot.noOfHours = noOfHours;
                    String reCreateSnapshotString = JSON.serialize(reCreateSnapshot);
                    Snapshot__c snapToBeInserted = new Snapshot__c();
                    snapToBeInserted.Id = snapshotId;
                    snapToBeInserted.Filter__c = EncodingUtil.urlEncode(reCreateSnapshotString, 'UTF-8');
                    DatabaseUtils.updateRecord(
                        snapToBeInserted,
                        new List<Schema.DescribeFieldResult>{ Snapshot__c.Filter__c.getDescribe() }
                    );
                    System.debug('reCreateSnapshotString---' + reCreateSnapshotString);
                } else {
                    System.debug('tempDt------' + null);
                    //Database.executeBatch(new ComponentQueryBatch(apexmetaTypeList, detail[0].AccessToken__c, detail[0].InstanceURL__c, snapshotId, null),1);
                    FlosumUtils.SnapshotFilterInfo tempFilterInfo = (FlosumUtils.SnapshotFilterInfo) JSON.deserialize(
                    	filterJSON,
                        FlosumUtils.SnapshotFilterInfo.class
                    );
                    tempFilterInfo.selectedNamespaceSet = new Set<String>();
                    if (nameSpaceSelectedList != null) {
                        for (SelectOption se : nameSpaceSelectedList) {
                            tempFilterInfo.selectedNamespaceSet.add(se.getValue());
                        }
                        tempFilterInfo.isNameSpaceSelected = true;
                    }

                    if (!IsApexCompleted) {
                        Database.executeBatch(
                            new ComponentQueryBatch(
                                apexmetaTypeList,
                                detail[0].AccessToken__c,
                                detail[0].InstanceURL__c,
                                snapshotId,
                                null,
                                JSON.serialize(tempFilterInfo)
                            ),
                            1
                        );
                    }

                    FlosumUtils.ReCreateSnapshotFilterWraper reCreateSnapshot = new FlosumUtils.ReCreateSnapshotFilterWraper(
                    	apexmetaTypeList,
                        null,
                        tempFilterInfo
                    );
                    String reCreateSnapshotString = JSON.serialize(reCreateSnapshot);
                    Snapshot__c snapToBeInserted = new Snapshot__c();
                    snapToBeInserted.Id = snapshotId;
                    snapToBeInserted.Filter__c = EncodingUtil.urlEncode(reCreateSnapshotString, 'UTF-8');
                    DatabaseUtils.updateRecord(
                        snapToBeInserted,
                        new List<Schema.DescribeFieldResult>{ Snapshot__c.Filter__c.getDescribe() }
                    );
                    System.debug('reCreateSnapshotString---' + reCreateSnapshotString);
                }
            }
        }

        return new PageReference('/' + snapshotId);
    }

    public static void insertLog(Id snapshotId) {
        List<Metadata_Log__c> logLi = new List<Metadata_Log__c>();
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Metadata_Log__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Process_Type__c.getDescribe(),
                    Metadata_Log__c.Snapshot__c.getDescribe(),
                    Metadata_Log__c.Status__c.getDescribe(),
                    Metadata_Log__c.Async_Request_Id__c.getDescribe()
                },
                Snapshot__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
            }
        );
        logLi = [
            SELECT Id, Process_Type__c, Snapshot__r.Name
            FROM Metadata_Log__c
            WHERE
                Snapshot__c = :snapshotId
                AND Process_Type__c = :FlosumConstants.PROCESS_SNAPSHOT_LOG_JS
                AND Status__c = :FlosumConstants.STATUS_IN_PROGRESS
                AND Async_Request_Id__c = NULL
        ];
        if (logLi.size() > 0) {
            List<Attachment> attLi = new List<Attachment>();
            for (Metadata_Log__c log : logLi) {
                Attachment att = new Attachment(ParentId = log.Id);
                att.Name = log.Snapshot__r.Name + ' Logfile';
                att.Body = Blob.valueOf('');
                if (log.Process_Type__c == FlosumConstants.PROCESS_SNAPSHOT_LOG_JS)
                    att.Description = 'JS';
                else
                    att.Description = 'APEX';
                att.ContentType = 'text/plain';
                attLi.add(att);
            }
            if (attLi.size() > 0) {
                DatabaseUtils.insertRecords(
                    attLi,
                    new List<Schema.DescribeFieldResult>{
                        Attachment.Body.getDescribe(),
                        Attachment.Name.getDescribe(),
                        Attachment.Description.getDescribe(),
                        Attachment.ContentType.getDescribe(),
                        Attachment.ParentId.getDescribe()
                    }
                );
            }
        }
    }

    @RemoteAction
    public static void apexRetrievalCompleted(String snapId) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Metadata_Log__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Process_Type__c.getDescribe(),
                    Metadata_Log__c.Job_Completed__c.getDescribe(),
                    Metadata_Log__c.Status__c.getDescribe(),
                    Metadata_Log__c.Succeed__c.getDescribe(),
                    Metadata_Log__c.Snapshot__c.getDescribe()
                }
            }
        );
        List<Metadata_Log__c> logList = [
            SELECT Id, Process_Type__c, Job_Completed__c, Status__c, Succeed__c
            FROM Metadata_Log__c
            WHERE Snapshot__c = :snapId AND Process_Type__c = :FlosumConstants.PROCESS_SNAPSHOT_LOG_APEX
            LIMIT 1
            FOR UPDATE
        ];
        if (logList != null && logList.size() > 0) {
            logList[0].Job_Completed__c = true;
            logList[0].Status__c = FlosumConstants.STATUS_COMPLETED;
            logList[0].Succeed__c = true;
            DatabaseUtils.updateRecords(
                logList,
                new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Job_Completed__c.getDescribe(),
                    Metadata_Log__c.Status__c.getDescribe(),
                    Metadata_Log__c.Succeed__c.getDescribe()
                }
            );
        }
    }

    public static ExternalSnapshotService.DeclarativeFilter parsefiltersToExternalFormat(
    	FlosumUtils.ReCreateSnapshotFilterWraper reCreateSnapshot
    ) {
        Integer filterNumber = 1;
        ExternalSnapshotService.DeclarativeFilter declarativeFilter = new ExternalSnapshotService.DeclarativeFilter();
        Boolean isStandardFilter = false;
        //last modified date filters
        ExternalSnapshotService.Filter ft = new ExternalSnapshotService.Filter();
        ft.field = 'lastModifiedDate';
        if (reCreateSnapshot.noOfDays != null) {
            ft.option = 'greater than';
            ft.value = reCreateSnapshot.noOfDays.formatGMT('yyyy-MM-dd HH:mm:ss ') + 'GMT';
        } else {
            ft.option = 'not equals';
            ft.value = null;
        }
        declarativeFilter.filters.add(ft);
        declarativeFilter.logic = '(' + filterNumber;
        filterNumber++;

        if (reCreateSnapshot.snapShotFilter != null && reCreateSnapshot.snapShotFilter.IsRetrieveStandard) {
            //standard components filter
            if (reCreateSnapshot.snapShotFilter.IsRetrieveStandard) {
                ExternalSnapshotService.Filter ft2 = new ExternalSnapshotService.Filter();
                ft2.field = 'lastModifiedDate';
                ft2.option = 'less or equals';
                ft2.value = DateTime.newInstance(0).formatGMT('yyyy-MM-dd HH:mm:ss ') + 'GMT';
                declarativeFilter.filters.add(ft2);
                declarativeFilter.logic += ' OR ' + filterNumber;
                filterNumber++;
            }
        }
        //close last modified date filters.
        declarativeFilter.logic += ' )';

        if (reCreateSnapshot.snapShotFilter != null) {
            //null manageablestate filter
            ExternalSnapshotService.Filter stateFilter1 = new ExternalSnapshotService.Filter();
            stateFilter1.field = 'manageableState';
            stateFilter1.option = 'equals';
            stateFilter1.value = null;
            declarativeFilter.filters.add(stateFilter1);
            declarativeFilter.logic += ' AND (' + filterNumber;
            filterNumber++;
            //null namespaceprefix filter
            ExternalSnapshotService.Filter stateFilter5 = new ExternalSnapshotService.Filter();
            stateFilter5.field = 'namespacePrefix';
            stateFilter5.option = 'equals';
            stateFilter5.value = null;
            declarativeFilter.filters.add(stateFilter5);
            declarativeFilter.logic += ' OR ' + filterNumber;
            filterNumber++;
            //manageablestate filter
            ExternalSnapshotService.Filter stateFilter2 = new ExternalSnapshotService.Filter();
            stateFilter2.field = 'manageableState';
            stateFilter2.option = 'in';
            Set<String> states = FlosumConstants.manageableStateToRetrieveSet;
            states.remove(null);
            stateFilter2.value = String.join(new List<String>(states), ';');
            declarativeFilter.filters.add(stateFilter2);
            declarativeFilter.logic += ' OR ' + filterNumber;
            filterNumber++;
            //namespace selected filter
            if (
                reCreateSnapshot.snapShotFilter.isNameSpaceSelected == true &&
                reCreateSnapshot.snapShotFilter.selectedNamespaceSet != null &&
                reCreateSnapshot.snapShotFilter.selectedNamespaceSet.size() > 0
            ) {
                ExternalSnapshotService.Filter stateFilter3 = new ExternalSnapshotService.Filter();
                stateFilter3.field = 'namespacePrefix';
                if (reCreateSnapshot.snapShotFilter.selectedNamespaceSet.size() > 1) {
                    stateFilter3.option = 'in';
                } else {
                    stateFilter3.option = 'equals';
                }
                stateFilter3.value = String.join(
                    new List<String>(reCreateSnapshot.snapShotFilter.selectedNamespaceSet),
                    ';'
                );
                declarativeFilter.filters.add(stateFilter3);
                declarativeFilter.logic += ' OR ' + filterNumber;
                filterNumber++;
            }
            declarativeFilter.logic += ' )';
            //all other filters selected on UI
            if (reCreateSnapshot.snapShotFilter.filterList != null) {
                for (FlosumUtils.SnapshotFilterWraper wrap : reCreateSnapshot.snapShotFilter.filterList) {
                    if (
                        wrap.field != null &&
                        wrap.operator != null &&
                        wrap.value != null &&
                        wrap.field != '' &&
                        wrap.operator != '' &&
                        wrap.value != ''
                    ) {
                        ExternalSnapshotService.Filter ftOthers = new ExternalSnapshotService.Filter();
                        ftOthers.field = wrap.field;
                        ftOthers.option = wrap.operator;
                        ftOthers.value = wrap.value;
                        if (
                            (wrap.operator == 'equals' || wrap.operator == 'not equals') &&
                            wrap.value.split(',').size() > 1
                        ) {
                            ftOthers.option = wrap.operator == 'equals' ? 'in' : 'not in';
                            ftOthers.value = String.join(wrap.value.split(','), ';');
                        }
                        declarativeFilter.filters.add(ftOthers);
                        declarativeFilter.logic += ' AND ' + filterNumber;
                        filterNumber++;
                    }
                }
            }
            if (
                reCreateSnapshot.snapShotFilter.selectedComponentsName != null &&
                !reCreateSnapshot.snapShotFilter.selectedComponentsName.isEmpty()
            ) {
                Boolean extraFilter = false;
                String elogic = '';
                List<String> setTypes = new List<String>();
                for (String compType : reCreateSnapshot.snapShotFilter.selectedComponentsName.keySet()) {
                    List<String> compNames = reCreateSnapshot.snapShotFilter.selectedComponentsName.get(compType);
                    if (compNames.size() == 1 && compNames.contains('*')) {
                        //ignore this filter
                        ExternalSnapshotService.Filter tFilter = new ExternalSnapshotService.Filter();
                        tFilter.field = 'type';
                        tFilter.option = 'equals';
                        tFilter.value = compType;
                        declarativeFilter.filters.add(tFilter);

                        if (elogic == '') {
                            elogic = '' + filterNumber;
                        } else {
                            elogic += ' OR ' + filterNumber;
                        }
                        filterNumber = filterNumber + 1;
                        setTypes.add(compType);
                    } else {
                        ExternalSnapshotService.Filter tFilter = new ExternalSnapshotService.Filter();
                        tFilter.field = 'type';
                        tFilter.option = 'equals';
                        tFilter.value = compType;
                        declarativeFilter.filters.add(tFilter);

                        ExternalSnapshotService.Filter ftOthers = new ExternalSnapshotService.Filter();
                        ftOthers.field = 'fullName';
                        ftOthers.option = 'in';
                        ftOthers.value = String.join(compNames, ';');
                        declarativeFilter.filters.add(ftOthers);

                        if (elogic == '') {
                            elogic = '(' + filterNumber + ' AND ' + (filterNumber + 1) + ')';
                        } else {
                            elogic += ' OR (' + filterNumber + ' AND ' + (filterNumber + 1) + ')';
                        }
                        filterNumber = filterNumber + 2;
                    }
                }
                /*if(!setTypes.isEmpty()) {
                    ExternalSnapshotService.Filter tFilter = new ExternalSnapshotService.Filter();
                    tFilter.field = 'type';
                    tFilter.option = 'in';
                    tFilter.value = String.join(setTypes,';');
                    declarativeFilter.filters.add(tFilter);

                    if(elogic == '') {
                        elogic = ''+filterNumber;
                    } else {
                        elogic += ' OR '+filterNumber;
                    }
                    filterNumber = filterNumber+1;
                }*/
                if (elogic != '') {
                    declarativeFilter.logic += ' AND (' + elogic + ')';
                }
            }
        }
        return declarativeFilter;
    }

    @RemoteAction
    public static MetadataTypeResult createSnapshot(
        String snapshotName,
        String organisationId,
        Integer filterDate,
        String filterJSON,
        String selectedHours,
        String selectedTypesJSON
    ) {
        System.debug('selectedTypesJSON start >>>> ' + selectedTypesJSON);
        MetadataTypeResult result = new MetadataTypeResult();
        result.isExternal = ExternalSnapshotService.isExternalRetrievalEnabled();
        Credentials__c creds = Credentials__c.getOrgDefaults();
        if (creds != null && creds.Id != null)
            result.retrievalType = creds.Retrieval_Type__c == FlosumConstants.RETRIEVAL_TYPE_SERIALIZE
                ? FlosumConstants.RETRIEVAL_TYPE_SERIALIZE
                : FlosumConstants.RETRIEVAL_TYPE_DEFAULT;
        result.isSuccess = true;
        if (isExistDuplicateSnapshot(snapshotName)) {
            try {
                if (MetadataUtils.isSlotAvailable()) {
                    FlosumUtils.SnapshotFilterInfo tempFilterInfo = (FlosumUtils.SnapshotFilterInfo) JSON.deserialize(
                        filterJSON,
                        FlosumUtils.SnapshotFilterInfo.class
                    );
                    FlosumUtils.ReCreateSnapshotFilterWraper reCreateSnapshot = new FlosumUtils.ReCreateSnapshotFilterWraper(
                        new List<String>(),
                        System.now(),
                        tempFilterInfo
                    );
                    Set<String> noOfHoursSet = new Set<String>{ '1', '3', '6', '12' };
                    DateTime tempDt = null;
                    if (
                        filterDate != null &&
                        (filterDate != 0 || (filterDate == 0 && noOfHoursSet.contains(selectedHours)))
                    ) {
                        tempDt = System.now();
                        tempDt = tempDt.addDays(-filterDate);
                        if (noOfHoursSet.contains(selectedHours)) {
                            tempDt = tempDt.addHours(-(Integer.valueOf(selectedHours)));
                        }
                    }
                    reCreateSnapshot.noOfDays = tempDt;
                    reCreateSnapshot.noOfHours = selectedHours;
                    reCreateSnapshot.snapShotFilter = tempFilterInfo;
                    String reCreateSnapshotString = JSON.serialize(reCreateSnapshot);

                    if (result.isExternal) {
                        //create request on external server
                        FlosumUtils controller = new FlosumUtils();
                        FlosumUtils.AuthenticateDetails authDetails = controller.authenticateAnOrg(organisationId);
                        if (authDetails.isSuccess) {
                            ExternalSnapshotService.RetrieveRequest bodyObj = new ExternalSnapshotService.RetrieveRequest();
                            bodyObj.credentials.accessToken = authDetails.details.AccessToken__c;
                            bodyObj.credentials.instanceUrl = authDetails.details.InstanceURL__c;
                            bodyObj.credentials.refreshToken = authDetails.details.RefreshToken__c;
                            bodyObj.credentials.clientId = authDetails.clientId;
                            bodyObj.credentials.clientSecret = authDetails.clientSecret;
                            if (selectedTypesJSON != null && selectedTypesJSON != '') {
                                System.debug('selectedTypesJSON isExternal >>>> ' + selectedTypesJSON);
                                bodyObj.metadataTypes = (List<String>) JSON.deserialize(
                                    selectedTypesJSON,
                                    List<String>.class
                                );
                            }
                            bodyObj.declarativeFilter = parsefiltersToExternalFormat(reCreateSnapshot);
                            String endpoint = ExternalSnapshotService.ExternalJobURL;
                            String reqBody = JSON.serialize(bodyObj);
                            System.debug('reqBody>>> ' + reqBody);
                            String response = ExternalSnapshotService.makeApiCall(
                                endpoint,
                                JSON.serialize(bodyObj),
                                'POST'
                            );
                            ExternalSnapshotService.JobStatus status = (ExternalSnapshotService.JobStatus) JSON.deserialize(
                                response,
                                ExternalSnapshotService.JobStatus.class
                            );
                            if (status != null && status.jobId != null) {
                                Snapshot__c snap = new Snapshot__c();
                                snap.Organisation__c = organisationId;
                                snap.Name = snapshotName;
                                snap.External_Job_Id__c = status.jobId;
                                snap.Is_External_Snapshot__c = true;
                                snap.External_Status__c = ExternalSnapshotBatch.Request_InQueue;
                                snap.Last_Modified_In_Days__c = filterDate;
                                snap.Filter__c = EncodingUtil.urlEncode(reCreateSnapshotString, 'UTF-8');
                                DatabaseUtils.insertRecord(
                                    snap,
                                    new List<Schema.DescribeFieldResult>{
                                        Snapshot__c.Organisation__c.getDescribe(),
                                        Snapshot__c.Name.getDescribe(),
                                        Snapshot__c.External_Job_Id__c.getDescribe(),
                                        Snapshot__c.Is_External_Snapshot__c.getDescribe(),
                                        Snapshot__c.External_Status__c.getDescribe(),
                                        Snapshot__c.Filter__c.getDescribe(),
                                        Snapshot__c.Last_Modified_In_Days__c.getDescribe()
                                    }
                                );
                                bodyObj.credentials = null;
                                Attachment att = new Attachment();
                                att.Name = 'FilterBody.json';
                                att.Body = Blob.valueOf(JSON.serialize(bodyObj));
                                att.ParentId = snap.Id;
                                att.ContentType = 'application/json';
                                insert att;

                                result.isSuccess = true;
                                result.snapId = snap.Id;

                                List<Metadata_Log__c> logLi = new List<Metadata_Log__c>();
                                Metadata_Log__c ApexLogRecord = new Metadata_Log__c();
                                ApexLogRecord.Organisation__c = organisationId;
                                ApexLogRecord.Snapshot__c = snap.Id;
                                ApexLogRecord.Status__c = FlosumConstants.STATUS_IN_PROGRESS;
                                ApexLogRecord.Process_Type__c = FlosumConstants.PROCESS_SNAPSHOT_LOG_APEX;
                                logLi.add(ApexLogRecord);

                                Metadata_Log__c JSLogRecord = new Metadata_Log__c();
                                JSLogRecord.Organisation__c = organisationId;
                                JSLogRecord.Snapshot__c = snap.Id;
                                JSLogRecord.Status__c = FlosumConstants.STATUS_COMPLETED;
                                JSLogRecord.Job_Completed__c = true;
                                JSLogRecord.Process_Type__c = FlosumConstants.PROCESS_SNAPSHOT_LOG_JS;
                                logLi.add(JSLogRecord);
                                DatabaseUtils.insertRecords(
                                    logLi,
                                    new List<Schema.DescribeFieldResult>{
                                        Metadata_Log__c.Organisation__c.getDescribe(),
                                        Metadata_Log__c.Snapshot__c.getDescribe(),
                                        Metadata_Log__c.Status__c.getDescribe(),
                                        Metadata_Log__c.Job_Completed__c.getDescribe(),
                                        Metadata_Log__c.Process_Type__c.getDescribe()
                                    }
                                );
                                ExternalSnapshotBatch.init();
                                return result;
                            } else {
                                throw new CalloutException(status.message);
                            }
                        } else {
                            result.isSuccess = false;
                            result.errorMessage = authDetails.errorMessage;
                        }
                    } else {
                        Snapshot__c snap = new Snapshot__c(
                            Organisation__c = organisationId,
                            Name = snapshotName,
                            Last_Modified_In_Days__c = filterDate
                        );
                        snap.Filter__c = EncodingUtil.urlEncode(reCreateSnapshotString, 'UTF-8');
                        DatabaseUtils.insertRecord(
                            snap,
                            new List<Schema.DescribeFieldResult>{
                                Snapshot__c.Organisation__c.getDescribe(),
                                Snapshot__c.Name.getDescribe(),
                                Snapshot__c.Filter__c.getDescribe(),
                                Snapshot__c.Last_Modified_In_Days__c.getDescribe()
                            }
                        );

                        Metadata_Log__c ApexLogRecord = new Metadata_Log__c();
                        ApexLogRecord.Organisation__c = organisationId;
                        ApexLogRecord.Snapshot__c = snap.Id;
                        ApexLogRecord.Status__c = FlosumConstants.STATUS_IN_PROGRESS;
                        ApexLogRecord.Process_Type__c = FlosumConstants.PROCESS_SNAPSHOT_LOG_APEX;
                        DatabaseUtils.insertRecord(
                            ApexLogRecord,
                            new List<Schema.DescribeFieldResult>{
                                Metadata_Log__c.Organisation__c.getDescribe(),
                                Metadata_Log__c.Snapshot__c.getDescribe(),
                                Metadata_Log__c.Status__c.getDescribe(),
                                Metadata_Log__c.Process_Type__c.getDescribe()
                            }
                        );

                        Metadata_Log__c JSLogRecord = new Metadata_Log__c();
                        JSLogRecord.Organisation__c = organisationId;
                        JSLogRecord.Snapshot__c = snap.Id;
                        JSLogRecord.Status__c = FlosumConstants.STATUS_IN_PROGRESS;
                        JSLogRecord.Process_Type__c = FlosumConstants.PROCESS_SNAPSHOT_LOG_JS;
                        DatabaseUtils.insertRecord(
                            JSLogRecord,
                            new List<Schema.DescribeFieldResult>{
                                Metadata_Log__c.Organisation__c.getDescribe(),
                                Metadata_Log__c.Snapshot__c.getDescribe(),
                                Metadata_Log__c.Status__c.getDescribe(),
                                Metadata_Log__c.Process_Type__c.getDescribe()
                            }
                        );

                        result.snapId = snap.Id;
                        result.logId = JSLogRecord.Id;
                        insertLog(snap.Id);
                        List<Attachment> attList = [
                            SELECT Id
                            FROM Attachment
                            WHERE ParentId = :JSLogRecord.Id AND Description = 'JS'
                            LIMIT 1
                        ];
                        if (attList.size() == 1) {
                            result.jsAttachmentId = attList[0].Id;
                        }
                    }
                } else {
                    result.isSuccess = false;
                    result.errorMessage = FlosumConstants.NO_SLOT_AVAILABLE;
                }
            } catch (Exception ex) {
                result.isSuccess = false;
                result.errorMessage = ex.getMessage();
            }
        } else {
            result.isSuccess = false;
            result.errorMessage = 'Snapshot with this name already exists.';
        }
        return result;
    }

    @RemoteAction
    public static MetadataTypeResult createMetadataItems(String propertiesLiStr) {
        MetadataTypeResult result = new MetadataTypeResult();
        result.isSuccess = true;
        try {
            List<Metadata_Item__c> metaItemList = new List<Metadata_Item__c>();
            Map<String, Id> recordTypeMap = new Map<String, Id>();
            String fullObjectName = Schema.sObjectType.Metadata_Item__c.getName();
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    RecordType.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        RecordType.SobjectType.getDescribe()
                    }
                }
            );
            for (RecordType rt : [SELECT Id, Name FROM RecordType WHERE SobjectType = :fullObjectName])
                recordTypeMap.put(rt.Name, rt.Id);
            List<FileProperties> queryWrapLi = new List<FileProperties>();
            queryWrapLi = (List<FileProperties>) JSON.deserialize(propertiesLiStr, List<FileProperties>.class);
            for (FileProperties property : queryWrapLi) {
                if (recordTypeMap.containsKey(property.type)) {
                    Metadata_Item__c item = new Metadata_Item__c();
                    item.RecordTypeId = recordTypeMap.get(property.type);
                    item.Name__c = property.fullname;
                    item.API_Name__c = property.fullname;
                    item.Snapshot__c = property.snapId;
                    item.Label__c = property.fileName;
                    item.Last_Updated_By__c = property.lastModifiedByName;
                    item.Last_Modified_Date__c = DateTime.newInstance(Long.valueOf(property.lastModifiedDate));
                    if (property.attId != null && property.attId.length() == 18) {
                        item.Attachment_ID__c = property.attId;
                        item.Is_Retrieved__c = true;
                    } else
                        item.Is_Retrieved__c = false;
                    metaItemList.add(item);
                }
            }
            if (metaItemList.size() > 0) {
                DatabaseUtils.insertRecords(
                    metaItemList,
                    new List<Schema.DescribeFieldResult>{
                        Metadata_Item__c.RecordTypeId.getDescribe(),
                        Metadata_Item__c.Name__c.getDescribe(),
                        Metadata_Item__c.API_Name__c.getDescribe(),
                        Metadata_Item__c.Snapshot__c.getDescribe(),
                        Metadata_Item__c.Label__c.getDescribe(),
                        Metadata_Item__c.Last_Modified_Date__c.getDescribe(),
                        Metadata_Item__c.Last_Updated_By__c.getDescribe(),
                        Metadata_Item__c.Folder__c.getDescribe(),
                        Metadata_Item__c.Is_Retrieved__c.getDescribe(),
                        Metadata_Item__c.Attachment_ID__c.getDescribe()
                    }
                );
            }
        } catch (Exception ex) {
            result.isSuccess = false;
            result.errorMessage = ex.getMessage();
        }
        //result.errorMessage = '';

        return result;
    }

    @RemoteAction
    public static List<FileProperties> listPersonAccountRecordTypes(String orgDetailId) {
        System.debug('listPersonAccountRecordTypes');
        List<FileProperties> resultLi = new List<FileProperties>();

        List<Authorization_Details__c> detail = [
            SELECT Id, AccessToken__c, InstanceURL__c
            FROM Authorization_Details__c
            WHERE Id = :orgDetailId
            LIMIT 1
        ];
        if (detail != null && detail.size() > 0) {
            //List RecordType with API
            String query = 'SELECT Id,DeveloperName,IsPersonType,NamespacePrefix FROM RecordType WHERE SobjectType = \'Account\' AND IsPersonType=true';
            String endpoint =
                detail[0].InstanceURL__c +
                '/services/data/v52.0/query/?q=' +
                EncodingUtil.urlEncode(query, 'UTF-8');
            HttpRequest req = new HttpRequest();
            req.setHeader('Authorization', 'Bearer ' + detail[0].AccessToken__c);
            req.setHeader('Content-Type', 'application/json');
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(120000);
            System.debug('endpoint >>>>> ' + endpoint);
            System.debug('req >>>>> ' + req);
            Http httpreq = new Http();
            HttpResponse res = httpreq.send(req);
            String reqresponse = res.getBody();
            System.debug(reqresponse);
            //parsing resoponse and get the fullname of flow
            boolean isFound = JSON.deserializeUntyped(reqresponse) instanceof Map<String, Object>;
            if (isFound) {
                Map<String, Object> customFieldDefination = (Map<String, Object>) JSON.deserializeUntyped(reqresponse);
                Object classList = customFieldDefination.get('records');
                if (classList instanceof List<Object>) {
                    List<Object> tempList = (List<Object>) classList;
                    if (tempList != null && tempList.size() > 0) {
                        for (object fielddata : tempList) {
                            if (fielddata instanceof Map<string, object>) {
                                Map<string, object> tempMap = (Map<string, object>) fielddata;
                                String toolingFullName = String.valueof(tempMap.get('DeveloperName'));
                                Boolean IsPersonType = Boolean.valueof(tempMap.get('IsPersonType'));
                                String NamespacePrefix = String.valueof(tempMap.get('NamespacePrefix'));
                                String toolingId = String.valueof(tempMap.get('Id'));
                                if (IsPersonType == true) {
                                    if (NamespacePrefix != null && NamespacePrefix != '') {
                                        toolingFullName = 'PersonAccount.' + NamespacePrefix + '__' + toolingFullName;
                                    } else {
                                        toolingFullName = 'PersonAccount.' + toolingFullName;
                                    }
                                    FileProperties property = new FileProperties();
                                    property.id = toolingId;
                                    property.fullName = toolingFullName;
                                    property.fileName = 'objects/PersonAccount.object';
                                    property.type = 'RecordType';
                                    resultLi.add(property);
                                }
                            }
                        }
                    }
                }
            }
            return resultLi;
        }
        return null;
    }

    @RemoteAction
    public static String getByToolingAPI(
        String currentMetadataType,
        String listQueryStr,
        String orgDetailId,
        String nextRecordsUrl
    ) {
        List<FileProperties> resultLi = new List<FileProperties>();

        List<Authorization_Details__c> detail = [
            SELECT Id, AccessToken__c, InstanceURL__c
            FROM Authorization_Details__c
            WHERE Id = :orgDetailId
            LIMIT 1
        ];
        if (detail != null && detail.size() > 0) {
            String query = listQueryStr;
            String endpoint;
            if (nextRecordsUrl != null && nextRecordsUrl != '') {
                endpoint = detail[0].InstanceURL__c + '' + nextRecordsUrl;
            } else {
                endpoint =
                    detail[0].InstanceURL__c +
                    '/services/data/v52.0/tooling' +
                    '/query/?q=' +
                    EncodingUtil.urlEncode(query, 'UTF-8');
            }

            HttpRequest req = new HttpRequest();
            req.setHeader('Authorization', 'Bearer ' + detail[0].AccessToken__c);
            req.setHeader('Content-Type', 'application/json');
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(120000);
            Http httpreq = new Http();
            HttpResponse res = httpreq.send(req);
            if (res.getStatusCode() == 200) {
                //return res.getBody();
                return EncodingUtil.base64Encode(res.getBodyAsBlob());
            } else {
                throw new FlosumException(res.getBody());
            }
        } else {
            throw new FlosumException('Org not found.');
        }
    }

    @RemoteAction
    public static String getBySOQLAPI(
        String currentMetadataType,
        String listQueryStr,
        String orgDetailId,
        String nextRecordsUrl
    ) {
        List<FileProperties> resultLi = new List<FileProperties>();
        List<Authorization_Details__c> detail = [
            SELECT Id, AccessToken__c, InstanceURL__c
            FROM Authorization_Details__c
            WHERE Id = :orgDetailId
            LIMIT 1
        ];
        if (detail != null && detail.size() > 0) {
            String query = listQueryStr;
            String endpoint;
            if (nextRecordsUrl != null && nextRecordsUrl != '') {
                endpoint = detail[0].InstanceURL__c + '' + nextRecordsUrl;
            } else {
                endpoint =
                    detail[0].InstanceURL__c +
                    '/services/data/v52.0/query/?q=' +
                    EncodingUtil.urlEncode(query, 'UTF-8');
            }

            HttpRequest req = new HttpRequest();
            req.setHeader('Authorization', 'Bearer ' + detail[0].AccessToken__c);
            req.setHeader('Content-Type', 'application/json');
            req.setEndpoint(endpoint);
            req.setMethod('GET');
            req.setTimeout(120000);
            Http httpreq = new Http();
            HttpResponse res = httpreq.send(req);
            if (res.getStatusCode() == 200) {
                //return res.getBody();
                return EncodingUtil.base64Encode(res.getBodyAsBlob());
            } else {
                throw new FlosumException(res.getBody());
            }
        } else {
            throw new FlosumException('Org not found.');
        }
    }

    @RemoteAction
    public static List<FileProperties> listMetadataComponents(String listQueryStr, String orgDetailId) {
        List<FileProperties> resultLi = new List<FileProperties>();

        List<Authorization_Details__c> detail = [
            SELECT Id, AccessToken__c, InstanceURL__c
            FROM Authorization_Details__c
            WHERE Id = :orgDetailId
            LIMIT 1
        ];
        if (detail != null && detail.size() > 0) {
            List<QueryWraper> queryWrapLi = new List<QueryWraper>();
            queryWrapLi = (List<QueryWraper>) JSON.deserialize(listQueryStr, List<QueryWraper>.class);
            String logMetaType;
            MetadataService.MetadataPort service = MetadataUtils.createService(
                detail[0].AccessToken__c,
                detail[0].InstanceURL__c
            );
            List<MetadataService.FileProperties> propertiesLi = new List<MetadataService.FileProperties>();
            for (QueryWraper wrap : queryWrapLi) {
                List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery>();
                MetadataService.ListMetadataQuery queryLayout = new MetadataService.ListMetadataQuery();
                queryLayout.folder = wrap.metaFolder;
                queryLayout.type_x = wrap.metaType;
                logMetaType = wrap.metaType;
                queries.add(queryLayout);
                List<MetadataService.FileProperties> propertiesLi2 = service.listMetadata(
                    queries,
                    FlosumConstants.apiversion
                );
                if (propertiesLi2 != null && propertiesLi2.size() > 0) {
                    if (queryLayout.type_x == 'CustomField') {
                        for (MetadataService.FileProperties fileProperty : propertiesLi2) {
                            if (fileProperty.type_x == null) {
                                fileProperty.type_x = queryLayout.type_x;
                            }
                            if (!fileProperty.fullName.startsWith(queryLayout.folder + '.')) {
                                fileProperty.fileName = 'objects/' + queryLayout.folder + '.object';
                                fileProperty.fullName = queryLayout.folder + '.' + fileProperty.fullName;
                            }
                        }
                    }
                    propertiesLi.addAll(propertiesLi2);
                }
            }
            listQueryStr = null;
            //List RecordType with tooling API
            Map<String, String> personAccountMap = new Map<String, String>();
            if (logMetaType == 'RecordType') {
                String query = 'SELECT Id,DeveloperName,IsPersonType,NamespacePrefix FROM RecordType WHERE SobjectType = \'Account\'';
                String endpoint =
                    detail[0].InstanceURL__c +
                    '/services/data/v52.0/query/?q=' +
                    EncodingUtil.urlEncode(query, 'UTF-8');
                HttpRequest req = new HttpRequest();
                req.setHeader('Authorization', 'Bearer ' + detail[0].AccessToken__c);
                req.setHeader('Content-Type', 'application/json');
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setTimeout(120000);
                Http httpreq = new Http();
                HttpResponse res = httpreq.send(req);
                String reqresponse = res.getBody();
                System.debug(reqresponse);
                //parsing resoponse and get the fullname of flow
                boolean isFound = JSON.deserializeUntyped(reqresponse) instanceof Map<String, Object>;
                if (isFound) {
                    Map<String, Object> customFieldDefination = (Map<String, Object>) JSON.deserializeUntyped(
                        reqresponse
                    );
                    Object classList = customFieldDefination.get('records');
                    if (classList instanceof List<Object>) {
                        List<Object> tempList = (List<Object>) classList;
                        if (tempList != null && tempList.size() > 0) {
                            for (object fielddata : tempList) {
                                if (fielddata instanceof Map<string, object>) {
                                    Map<string, object> tempMap = (Map<string, object>) fielddata;
                                    String toolingFullName = String.valueof(tempMap.get('DeveloperName'));
                                    Boolean IsPersonType = Boolean.valueof(tempMap.get('IsPersonType'));
                                    String NamespacePrefix = String.valueof(tempMap.get('NamespacePrefix'));
                                    String toolingId = String.valueof(tempMap.get('Id'));
                                    if (IsPersonType == true) {
                                        if (NamespacePrefix != null && NamespacePrefix != '') {
                                            toolingFullName =
                                                'PersonAccount.' +
                                                NamespacePrefix +
                                                '__' +
                                                toolingFullName;
                                        } else {
                                            toolingFullName = 'PersonAccount.' + toolingFullName;
                                        }
                                        personAccountMap.put(toolingId, toolingFullName);
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (logMetaType == 'CompactLayout') {
                String query = 'SELECT Id,fullName FROM CompactLayout WHERE SObjectType = \'Account\'';
                String endpoint =
                    detail[0].InstanceURL__c +
                    '/services/data/v34.0/tooling' +
                    '/query/?q=' +
                    EncodingUtil.urlEncode(query, 'UTF-8');
                HttpRequest req = new HttpRequest();
                req.setHeader('Authorization', 'Bearer ' + detail[0].AccessToken__c);
                req.setHeader('Content-Type', 'application/json');
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setTimeout(120000);
                Http httpreq = new Http();
                HttpResponse res = httpreq.send(req);
                String reqresponse = res.getBody();
                System.debug(reqresponse);
                //parsing resoponse and get the fullname of flow
                boolean isFound = JSON.deserializeUntyped(reqresponse) instanceof Map<String, Object>;
                if (isFound) {
                    Map<String, Object> customFieldDefination = (Map<String, Object>) JSON.deserializeUntyped(
                        reqresponse
                    );
                    Object classList = customFieldDefination.get('records');
                    if (classList instanceof List<Object>) {
                        List<Object> tempList = (List<Object>) classList;
                        if (tempList != null && tempList.size() > 0) {
                            for (object fielddata : tempList) {
                                if (fielddata instanceof Map<string, object>) {
                                    Map<string, object> tempMap = (Map<string, object>) fielddata;
                                    String toolingFullName = string.valueof(tempMap.get('FullName'));
                                    String toolingId = string.valueof(tempMap.get('Id'));
                                    personAccountMap.put(toolingId, toolingFullName);
                                }
                            }
                        }
                    }
                }
            }
            if (logMetaType == 'StandardValueSet' && (propertiesLi == null || propertiesLi.size() == 0)) {
                propertiesLi = new List<MetadataService.FileProperties>();
                for (String valueSetName : FlosumConstants.standardValueSet) {
                    MetadataService.FileProperties fileProperty = new MetadataService.FileProperties();
                    fileProperty.fullName = valueSetName;
                    fileProperty.fileName = 'standardValueSets/' + valueSetName + '.standardValueSet';
                    fileProperty.lastModifiedByName = '';
                    fileProperty.lastModifiedDate = DateTime.newInstance(0);
                    fileProperty.type_x = logMetaType;
                    propertiesLi.add(fileProperty);
                }
            }
            if (propertiesLi != null) {
                String fullObjectName = Schema.sObjectType.Metadata_Item__c.getName();
                Map<String, Id> RecordTypeMap = new Map<String, Id>();
                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        RecordType.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            RecordType.IsActive.getDescribe(),
                            RecordType.SobjectType.getDescribe()
                        }
                    }
                );
                for (RecordType rt : [
                    SELECT Name, Id
                    FROM RecordType
                    WHERE IsActive = TRUE AND SobjectType = :fullObjectName
                    LIMIT 1000
                ])
                    RecordTypeMap.put(rt.Name, rt.Id);
                Set<String> componentNameSet = new Set<String>();
                for (MetadataService.FileProperties fileProperty : propertiesLi) {
                    if (fileProperty.type_x == null) {
                        fileProperty.type_x = logMetaType;
                    }
                    fileProperty = FlosumConstants.fixNamesOfItems(fileProperty);
                    if (personAccountMap.containsKey(fileProperty.Id)) {
                        String recordTypeFullName = personAccountMap.get(fileProperty.Id);
                        if (recordTypeFullName.startsWithIgnoreCase('PersonAccount.')) {
                            fileProperty.fullName = recordTypeFullName;
                            fileProperty.fileName = 'objects/PersonAccount.object';
                        }
                    }
                    if (
                        !componentNameSet.contains(fileProperty.fullname) &&
                        RecordTypeMap.containsKey(fileProperty.type_x)
                    ) {
                        resultLi.add(new FileProperties(fileProperty));
                        componentNameSet.add(fileProperty.fullName);
                    }
                }
                componentNameSet.clear();
                propertiesLi.clear();
            }
            return resultLi;
        }
        return null;
    }
    @JsonAccess(serializable='always' deserializable='always')
    public class SOQLResposeResult {
        public boolean isDone;
        public Integer totalRecords;
        public String nextRecordURI;
        public List<FileProperties> resultLi;

        public SOQLResposeResult() {
            isDone = true;
            resultLi = new List<FileProperties>();
        }

        public SOQLResposeResult(String reqresponse) {
            this.isDone = true;
            this.resultLi = new List<FileProperties>();
            boolean isFound = JSON.deserializeUntyped(reqresponse) instanceof Map<String, Object>;
            if (isFound) {
                Map<String, Object> customFieldDefination = (Map<String, Object>) JSON.deserializeUntyped(reqresponse);
                Object classList = customFieldDefination.get('records');
                this.isDone = (Boolean) customFieldDefination.get('done');
                this.nextRecordURI = (String) customFieldDefination.get('nextRecordsUrl');
                if (classList instanceof List<Object>) {
                    List<Object> tempList = (List<Object>) classList;
                    if (tempList != null && tempList.size() > 0) {
                        for (object fielddata : tempList) {
                            if (fielddata instanceof Map<string, object>) {
                                Map<String, object> tempMap = (Map<String, object>) fielddata;
                                String LastModifiedDateStr = String.valueof(tempMap.get('LastModifiedDate'));
                                LastModifiedDateStr = LastModifiedDateStr.replace('T', ' ');
                                DateTime LastModifiedDate = DateTime.valueOfGmt(LastModifiedDateStr);
                                Object modifiedByObj = tempMap.get('LastModifiedBy');
                                String toolingId = String.valueof(tempMap.get('id'));
                                Object recAtt = tempMap.get('attributes');
                                if (
                                    modifiedByObj != null &&
                                    modifiedByObj instanceof Map<string, object> &&
                                    recAtt instanceof Map<string, object>
                                ) {
                                    Map<String, object> tempMap4 = (Map<String, object>) modifiedByObj;
                                    String LastModifiedBy = String.valueof(tempMap4.get('Name'));

                                    Map<String, object> tempMap5 = (Map<String, object>) recAtt;
                                    String metaItemType = String.valueof(tempMap5.get('type'));
                                    String fullName;
                                    String fileName;
                                    FileProperties property = new FileProperties();
                                    if (metaItemType == 'UserRole') {
                                        property.type = 'Role';
                                        fullName = String.valueof(tempMap.get('DeveloperName'));
                                        fileName = 'roles/' + fullName + '.role';
                                    } else if (metaItemType == 'Document') {
                                        property.type = 'Document';
                                        Object folderInfo = tempMap.get('Folder');
                                        Map<String, object> tempMap6 = (Map<String, object>) folderInfo;
                                        String folderName = String.valueof(tempMap6.get('DeveloperName'));
                                        String NamespacePrefix = String.valueof(tempMap.get('NamespacePrefix'));
                                        if (NamespacePrefix != null && NamespacePrefix != '')
                                            fullName =
                                                NamespacePrefix +
                                                '__' +
                                                folderName +
                                                '/' +
                                                NamespacePrefix +
                                                '__' +
                                                String.valueof(tempMap.get('DeveloperName')) +
                                                '.' +
                                                tempMap.get('Type');
                                        else
                                            fullName =
                                                folderName +
                                                '/' +
                                                String.valueof(tempMap.get('DeveloperName')) +
                                                '.' +
                                                tempMap.get('Type');
                                        fileName = 'documents/' + fullName;
                                    } else if (metaItemType == 'Folder' && tempMap.get('Type') == 'EmailTemplate') {
                                        property.type = 'EmailFolder';
                                        fullName = String.valueof(tempMap.get('DeveloperName'));
                                        fileName = 'email/' + fullName;
                                    } else
                                        property.type = metaItemType;

                                    property.id = toolingId;
                                    property.fileName = fileName;
                                    property.fullName = fullName;
                                    property.lastModifiedDate = '' + LastModifiedDate.getTime();
                                    property.changedOn = LastModifiedDate.format();
                                    property.createdDate = ''; //CreatedDateStr;
                                    property.createdOn = ''; //CreatedDate.format();
                                    property.createdByName = ''; //CreatedBy;
                                    property.lastModifiedByName = LastModifiedBy;

                                    this.resultLi.add(property);
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @RemoteAction
    public static SOQLResposeResult listMetadataTypeBySOQL(String queryStr, String orgDetailId) {
        try {
            List<FileProperties> resultLi = new List<FileProperties>();

            List<Authorization_Details__c> detail = [
                SELECT Id, AccessToken__c, InstanceURL__c
                FROM Authorization_Details__c
                WHERE Id = :orgDetailId
                LIMIT 1
            ];
            if (detail != null && detail.size() > 0) {
                System.debug(queryStr);
                String endpoint;
                if (queryStr.containsIgnoreCase('SELECT Id'))
                    endpoint =
                        detail[0].InstanceURL__c +
                        '/services/data/v51.0/query/?q=' +
                        EncodingUtil.urlEncode(queryStr, 'UTF-8');
                else
                    endpoint = detail[0].InstanceURL__c + queryStr;

                HttpRequest req = new HttpRequest();
                req.setHeader('Authorization', 'Bearer ' + detail[0].AccessToken__c);
                req.setHeader('Content-Type', 'application/json');
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setTimeout(120000);
                Http httpreq = new Http();
                HttpResponse res = httpreq.send(req);
                String reqresponse = res.getBody();
                return new SOQLResposeResult(reqresponse);
                //parsing resoponse and get the fullname of role
            }
        } catch (Exception ex) {
        }
        return new SOQLResposeResult();
    }

    @RemoteAction
    public static List<FileProperties> listFlows(String orgDetailId, List<String> flowIds) {
        System.debug(flowIds);
        List<FileProperties> resultLi = new List<FileProperties>();

        List<Authorization_Details__c> detail = [
            SELECT Id, AccessToken__c, InstanceURL__c
            FROM Authorization_Details__c
            WHERE Id = :orgDetailId
            LIMIT 1
        ];
        if (detail != null && detail.size() > 0) {
            if (flowIds.size() > 0) {
                String SOQL_IDs = '';
                for (String flowId : flowIds) {
                    String id_in_quotes = '\'' + flowId + '\'';
                    if (SOQL_IDs != '') {
                        SOQL_IDs += ',';
                    } //  add a comma if this isn't the first one
                    SOQL_IDs += id_in_quotes;
                }
                String query = 'SELECT Id,fullName FROM Flow WHERE ID IN (' + SOQL_IDs + ')';
                String endpoint =
                    detail[0].InstanceURL__c +
                    '/services/data/v51.0/tooling' +
                    '/query/?q=' +
                    EncodingUtil.urlEncode(query, 'UTF-8');
                HttpRequest req = new HttpRequest();
                req.setHeader('Authorization', 'Bearer ' + detail[0].AccessToken__c);
                req.setHeader('Content-Type', 'application/json');
                req.setEndpoint(endpoint);
                req.setMethod('GET');
                req.setTimeout(120000);
                Http httpreq = new Http();
                HttpResponse res = httpreq.send(req);
                String reqresponse = res.getBody();
                //parsing resoponse and get the fullname of flow
                boolean isFound = JSON.deserializeUntyped(reqresponse) instanceof Map<String, Object>;
                if (isFound) {
                    Map<String, Object> customFieldDefination = (Map<String, Object>) JSON.deserializeUntyped(
                        reqresponse
                    );
                    Object classList = customFieldDefination.get('records');
                    if (classList instanceof List<Object>) {
                        List<Object> tempList = (List<Object>) classList;
                        if (tempList != null && tempList.size() > 0) {
                            for (object fielddata : tempList) {
                                if (fielddata instanceof Map<string, object>) {
                                    List<Metadata_Item__c> metaItemList = new List<Metadata_Item__c>();
                                    Map<string, object> tempMap = (Map<string, object>) fielddata;
                                    String toolingFullName = string.valueof(tempMap.get('FullName'));
                                    String toolingId = string.valueof(tempMap.get('Id'));

                                    FileProperties property = new FileProperties();
                                    property.id = toolingId;
                                    property.fileName = 'flows/' + toolingFullName + '.flow';
                                    property.fullName = toolingFullName;
                                    resultLi.add(property);
                                }
                            }
                        }
                    }
                }
            }
        }
        return resultLi;
    }

    public static boolean isExistDuplicateSnapshot(String snapshotName) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Snapshot__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
            }
        );
        List<Snapshot__c> snapshotLi = [SELECT Name FROM Snapshot__c WHERE Name = :snapshotName LIMIT 1];
        if (snapshotLi != null && snapshotLi.size() > 0)
            return false;
        return true;
    }
    @JsonAccess(serializable='always' deserializable='always')
    public class FileProperties {
        //public String createdById;
        public String createdByName;
        public String createdOn;
        public String createdDate;
        public String fileName;
        public String fullName;
        public String id;
        //public String lastModifiedById;
        public String lastModifiedByName;
        public String lastModifiedDate;
        public String changedOn;
        public String manageableState;
        public String namespacePrefix;
        public String type;
        public String snapId;
        public String attId;

        public FileProperties(MetadataService.FileProperties property) {
            this.fileName = property.fileName;
            this.fullName = property.fullName;
            this.id = property.id;
            this.lastModifiedByName = property.lastModifiedByName;
            if (property.lastModifiedDate != null) {
                this.lastModifiedDate = '' + property.lastModifiedDate.getTime(); //property.lastModifiedDate;
                this.changedOn = property.lastModifiedDate.format();
            }
            if (property.createdDate != null) {
                this.createdDate = '' + property.createdDate.getTime(); //property.lastModifiedDate;
                this.createdOn = property.createdDate.format();
            }
            this.manageableState = property.manageableState;
            this.namespacePrefix = property.namespacePrefix;
            this.type = property.type_x;
            this.createdByName = property.createdByName;
        }

        public FileProperties() {
        }
    }
    @JsonAccess(serializable='always' deserializable='always')
    public class MetadataTypeResult {
        public boolean isSuccess;
        public String snapId;
        public String logId;
        public String errorMessage;
        public String retrievalType;
        public String jsAttachmentId;
        public Boolean isExternal;
    }
    @JsonAccess(serializable='always' deserializable='always')
    public class QueryWraper {
        public String metaType;
        public String metaFolder;
    }
}