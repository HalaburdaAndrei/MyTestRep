public with sharing class JSSnapshotRetrievalController {
    public Set<String> JSRetrievalMetadataTypeSet = new Set<String>{ 'Profile' };
    public Credentials__c cred { get; set; }
    public Map<String, List<String>> MultiMetaItems { get; set; }
    public String snapshotName { get; set; }
    public Integer filterDate { get; set; }
    public boolean isSuccessful { get; set; }

    public String session { get; set; }
    public String instance { get; set; }
    public String orgname { get; set; }
    public String refereshToken { get; set; }
    public String currentOrgSessionId { get; set; }
    public String organisationId;

    //private List<Authorization_Details__c> detail;
    private AuthUtils.AuthenticateDetails authDetails;
    private String canBeReAuthenticated;
    public List<MetaTypeWraper> metatypesList { get; set; }

    public String sanpshotId { get; set; }
    public String logRecordId { get; set; }
    public long filterMiliSeconds { get; set; }
    public String typesStr { get; set; }

    public String message { get; set; }
    public String NameSpacePrefix { get; set; }
    public Integer localApiVersion { get; private set; }

    public JSSnapshotRetrievalController() {
        System.debug('JSSnapshotRetrievalController');
        localApiVersion = FlosumConstants.apiversion;
        isSuccessful = false;
        currentOrgSessionId = UserInfo.getSessionId();
        cred = (Credentials__c.getOrgDefaults() != null &&
            Credentials__c.getOrgDefaults().id != null)
            ? Credentials__c.getOrgDefaults()
            : new Credentials__c();
        NameSpacePrefix = FlosumConstants.getNameSpacePrefix();
        sanpshotId = '';
        metatypesList = new List<MetaTypeWraper>();
        this.snapshotName = '';
        filterDate = 14;
        MultiMetaItems = new Map<String, List<String>>();

        organisationId = ApexPages.currentPage().getParameters().get('oid') != null
            ? ApexPages.currentPage().getParameters().get('oid')
            : null;
        try {
            List<Organisation__c> org = new List<Organisation__c>();
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Organisation__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Organisation__c.Organisation_Type__c.getDescribe(),
                        Organisation__c.HostName__c.getDescribe(),
                        Organisation__c.Username__c.getDescribe(),
                        Organisation__c.Name.getDescribe()
                    }
                }
            );
            org = [
                SELECT id, Organisation_Type__c, HostName__c, Username__c, Name
                FROM Organisation__c
                WHERE id = :organisationId
                LIMIT 1
            ];
            if (org.size() > 0) {
                authDetails = AuthUtils.authenticateAnOrg(organisationId, FlosumConstants.DEVELOPER);
                if (authDetails.isSuccess) {
                    this.session = authDetails.details.AccessToken__c;
                    this.instance = authDetails.details.InstanceURL__c;
                    this.refereshToken = authDetails.details.RefreshToken__c;
                    this.orgname = org[0].Name;
                    ApexPages.addMessage(
                        new ApexPages.Message(ApexPages.Severity.INFO, FlosumConstants.SNAPSHOT_PERFORMANCE_TIP_2)
                    );
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, authDetails.infoMessage));
                } else {
                    ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, authDetails.errorMessage));
                    return;
                }
            } else {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, 'Organization Not Found'));
                return;
            }

            // List available Metadata Types via the 'describeMetadata' API call
            MetadataService.MetadataPort service = MetadataUtils.createService(this.session, this.instance);
            MetadataService.DescribeMetadataResult describeResult = service.describeMetadata(
                FlosumConstants.apiversion
            );
            List<String> metadataTypeNames = new List<String>();
            for (MetadataService.DescribeMetadataObject metadataObject : describeResult.metadataObjects) {
                metadataTypeNames.add(metadataObject.xmlName);
                // Include child Metadata Types (such as CustomField, ValidationRule etc..)

                if (metadataObject.childXmlNames != null) {
                    for (String childXmlName : metadataObject.childXmlNames) {
                        if (childXmlName != null) {
                            metadataTypeNames.add(childXmlName);
                        }
                    }
                }
            }
            // Sort Metadata Types
            metadataTypeNames.sort();
            for (String metadataTypeName : metadataTypeNames) {
                if (FlosumConstants.metaDataTypeFilterSet.contains(metadataTypeName) || Test.isRunningTest()) {
                    if (metadataTypeName != 'CustomLabels')
                        metatypesList.add(new MetaTypeWraper(false, metadataTypeName));
                }
            }
        } catch (Exception e) {
            if (e.getMessage().contains(' INVALID_OPERATION_WITH_EXPIRED_PASSWORD'))
                ApexPages.addMessage(
                    new ApexPages.Message(ApexPages.Severity.Error, 'Oraganisation password has been expired.')
                );
            else
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, e.getMessage()));
        }
    }

    public void sessionReferesh() {
        currentOrgSessionId = UserInfo.getSessionId();
    }

    public void snapshotAction() {
        if (authDetails != null && authDetails.needToUpdateDetails) {
            update authDetails.details;
        }
    }

    // List Metadata items for the selected Metadata Type
    public PageReference listMetadataItems() {
        if (filterDate < 0) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Error, 'Please enter a positive number.'));
            return null;
        }
        sanpshotId = '';
        typesStr = '';
        logRecordId = '';

        try {
            List<String> jsmetaTypeList = new List<String>();
            List<String> apexmetaTypeList = new List<String>();
            for (MetaTypeWraper mType : metatypesList) {
                if (mType.selected) {
                    if (JSRetrievalMetadataTypeSet.contains(mType.metatype))
                        jsmetaTypeList.add(mType.metatype);
                    else
                        apexmetaTypeList.add(mType.metatype);
                }
            }
            if (checkDuplicate(this.snapshotName)) {
                if (
                    (jsmetaTypeList.size() > 0 ||
                    apexmetaTypeList.size() > 0) &&
                    this.snapshotName != null &&
                    this.snapshotName.trim() != ''
                ) {
                    if (MetadataUtils.isSlotAvailable()) {
                        filterMiliSeconds = 0;
                        DateTime tempDt = System.now();
                        if (filterDate != null && filterDate != 0) {
                            tempDt = tempDt.addDays(-filterDate);
                            filterMiliSeconds = tempDt.getTime();
                        }

                        Snapshot__c snap = new Snapshot__c(
                            Organisation__c = this.organisationId,
                            Name = this.snapshotName,
                            Last_Modified_In_Days__c = filterDate
                        );
                        DatabaseUtils.insertRecord(
                            snap,
                            new List<Schema.DescribeFieldResult>{
                                Snapshot__c.Organisation__c.getDescribe(),
                                Snapshot__c.Name.getDescribe(),
                                Snapshot__c.Last_Modified_In_Days__c.getDescribe()
                            }
                        );

                        /*Metadata_Log__c logRecord = new Metadata_Log__c();
                        logRecord.Organisation__c = this.organisationId;
                        logRecord.Snapshot__c = snap.Id;
                        logRecord.Status__c = FlosumConstants.STATUS_IN_PROGRESS;
                        logRecord.Process_Type__c = FlosumConstants.PROCESS_SNAPSHOT_LOG;
                        insert logRecord;*/

                        Metadata_Log__c ApexLogRecord = new Metadata_Log__c();
                        ApexLogRecord.Organisation__c = this.organisationId;
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
                        JSLogRecord.Organisation__c = this.organisationId;
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

                        if (jsmetaTypeList.size() > 0) {
                            logRecordId = JSLogRecord.Id;
                            sanpshotId = snap.Id;

                            typesStr = JSON.serialize(jsmetaTypeList);
                            if (apexmetaTypeList.size() > 0) {
                                if (filterDate != null && filterDate != 0) {
                                    Database.executeBatch(
                                        new ComponentQueryBatch(
                                            apexmetaTypeList,
                                            this.session,
                                            this.instance,
                                            snap.Id,
                                            tempDt,
                                            null
                                        ),
                                        1
                                    );
                                } else {
                                    Database.executeBatch(
                                        new ComponentQueryBatch(
                                            apexmetaTypeList,
                                            this.session,
                                            this.instance,
                                            snap.Id,
                                            null,
                                            null
                                        ),
                                        1
                                    );
                                }
                            } else {
                                ApexLogRecord.Job_Completed__c = true;
                                ApexLogRecord.Status__c = FlosumConstants.STATUS_COMPLETED;
                                ApexLogRecord.Succeed__c = true;
                                DatabaseUtils.updateRecord(
                                    ApexLogRecord,
                                    new List<Schema.DescribeFieldResult>{
                                        Metadata_Log__c.Job_Completed__c.getDescribe(),
                                        Metadata_Log__c.Status__c.getDescribe(),
                                        Metadata_Log__c.Succeed__c.getDescribe()
                                    }
                                );
                                //snap.Apex_Is_Completed__c = true;
                                //update snap;
                            }
                        } else {
                            JSLogRecord.Job_Completed__c = true;
                            JSLogRecord.Status__c = FlosumConstants.STATUS_COMPLETED;
                            JSLogRecord.Succeed__c = true;
                            DatabaseUtils.updateRecord(
                                JSLogRecord,
                                new List<Schema.DescribeFieldResult>{
                                    Metadata_Log__c.Job_Completed__c.getDescribe(),
                                    Metadata_Log__c.Status__c.getDescribe(),
                                    Metadata_Log__c.Succeed__c.getDescribe()
                                }
                            );
                            //snap.JS_Is_Completed__c = true;
                            //update snap;
                            if (filterDate != null && filterDate != 0) {
                                Database.executeBatch(
                                    new ComponentQueryBatch(
                                        apexmetaTypeList,
                                        this.session,
                                        this.instance,
                                        snap.Id,
                                        tempDt,
                                        null
                                    ),
                                    1
                                );
                            } else {
                                Database.executeBatch(
                                    new ComponentQueryBatch(
                                        apexmetaTypeList,
                                        this.session,
                                        this.instance,
                                        snap.Id,
                                        null,
                                        null
                                    ),
                                    1
                                );
                            }
                            return new PageReference('/' + snap.Id);
                        }
                        ApexPages.addMessage(
                            new ApexPages.Message(ApexPages.Severity.INFO, 'Please wait, Retrieval is in progress...')
                        );
                    } else {
                        ApexPages.addMessage(
                            new ApexPages.Message(ApexPages.Severity.Error, FlosumConstants.NO_SLOT_AVAILABLE)
                        );
                    }
                } else if (jsmetaTypeList.size() == 0 && apexmetaTypeList.size() == 0) {
                    ApexPages.addMessage(
                        new ApexPages.Message(ApexPages.Severity.Error, 'Please Select at least one Metadata Type.')
                    );
                } else {
                    ApexPages.addMessage(
                        new ApexPages.Message(ApexPages.Severity.Error, 'Please Enter Snapshot Name.')
                    );
                }
            }
        } catch (DatabaseUtilsException e) {
            System.debug(e.getMessage());
            ApexPages.addMessage(
                new ApexPages.Message(ApexPages.Severity.WARNING, 'Permission denied: ' + e.getMessage())
            );
        }

        return null;
    }

    public Boolean checkDuplicate(String snapshotname) {
        List<Snapshot__c> snapshot = new List<Snapshot__c>();
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Snapshot__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Snapshot__c.Name.getDescribe()
                }
            }
        );
        snapshot = [SELECT Name FROM Snapshot__c WHERE Name = :snapshotname LIMIT 1];
        if (snapshot.size() > 0) {
            ApexPages.addMessage(
                new ApexPages.Message(ApexPages.Severity.Info, 'Snapshot with this name already exists.')
            );
            return false;
        } else {
            return true;
        }
    }

    public PageReference completeRetrieval() {
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
            WHERE Snapshot__c = :sanpshotId AND Process_Type__c = :FlosumConstants.PROCESS_SNAPSHOT_LOG_JS
            LIMIT 1
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
        return new PageReference('/' + sanpshotId);
        /*List<Snapshot__c> snapList = new List<Snapshot__c>();
        snapList = [SELECT Id,Name,JS_Is_Completed__c,Is_Error__c From Snapshot__c WHERE Id=:sanpshotId LIMIT 1];
        if(snapList.size() == 1)
        {
            snapList[0].JS_Is_Completed__c = true;
            snapList[0].Is_Error__c = isSuccessful;
            update snapList;
            return new PageReference('/'+snapList[0].Id);
        }
        else
        {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.Info, 'Snapshot not found.'));
        }
        return null;*/
    }

    public void showMessage() {
        if (message != null) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, message));
        }
    }

    @RemoteAction
    public static List<String> insertMetaItems(String snapId, String metaJSN) {
        List<MetaItemWraper> metaList = new List<MetaItemWraper>();
        metaList = (List<MetaItemWraper>) JSON.deserialize(metaJSN, List<MetaItemWraper>.class);
        List<Metadata_Item__c> metaItemList = new List<Metadata_Item__c>();
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        String fullObjectName = Schema.sObjectType.Metadata_Item__c.getName();
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                RecordType.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    RecordType.Name.getDescribe(),
                    RecordType.SobjectType.getDescribe()
                }
            }
        );
        for (RecordType rt : [SELECT Id, Name FROM RecordType WHERE SobjectType = :fullObjectName]) {
            recordTypeMap.put(rt.Name, rt.Id);
        }
        for (MetaItemWraper wrap : metaList) {
            if (recordTypeMap.containsKey(wrap.type)) {
                Metadata_Item__c item = new Metadata_Item__c();
                item.RecordTypeId = recordTypeMap.get(wrap.type);
                item.Name__c = wrap.fullname;
                item.API_Name__c = wrap.fullname; //MetadataUtils.getAPIName(item.Name__c);
                item.Snapshot__c = snapId;
                item.Label__c = wrap.fileName;
                item.Last_Updated_By__c = wrap.lastModifiedByName;
                String str = wrap.lastModifiedDate.replace('T', ' ');
                item.Last_Modified_Date__c = DateTime.valueOfGMT(str);
                item.Folder__c = wrap.folder;
                item.Attachment_ID__c = wrap.attachemntId == '' ? null : wrap.attachemntId;
                item.Is_Retrieved__c = true;
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
                    Metadata_Item__c.Attachment_ID__c.getDescribe(),
                    Metadata_Item__c.Is_Retrieved__c.getDescribe()
                }
            );
        }
        return new List<String>{ snapId };
    }
    @JsonAccess(serializable='always' deserializable='always')
    public class MetaItemWraper {
        public String fullName; //wrapItem.fullName
        public String fileName; //wrapItem.fileName
        public String lastModifiedByName; //wrapItem.lastModifiedByName
        public String lastModifiedDate; //wrapItem.lastModifiedDate
        public String type; //wrapItem.type
        public String attachemntId; //
        public String folder; //
    }
    @JsonAccess(serializable='always' deserializable='always')
    public class OrgDetailWraper {
        public String sessionId;
        public String orgInstance;
        public String refereshToken;
    }
    @JsonAccess(serializable='always' deserializable='always')
    public class MetaTypeWraper {
        public boolean selected { get; set; }
        public String metatype { get; set; }

        public MetaTypeWraper(boolean selected, String metatype) {
            this.selected = selected;
            this.metatype = metatype;
        }
    }
}