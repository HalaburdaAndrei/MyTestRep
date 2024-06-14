public with sharing class ComponentQueryBatch implements Database.batchable<sobject>, Database.AllowsCallouts, Database.Stateful {
    private String session;
    private String instance;
    private Id snapId;
    private String query = 'SELECT Id FROM Snapshot__c WHERE id=\'';
    public MetadataService.MetadataPort service;

    private String fullObjectName;
    private DateTime filterDate;

    public Set<String> metadataTypeSet = new Set<String>();
    private Map<String, Id> RecordTypeMap = new Map<String, Id>();
    private List<Metadata_Item__c> globalItemsList = new List<Metadata_Item__c>();

    public Set<String> filterSet = new Set<String>{ 'CustomField', 'Document', 'Dashboard', 'Report', 'EmailTemplate' };
    public String retrievalLog = '';

    public FlosumUtils.SnapshotFilterInfo filterInfo = new FlosumUtils.SnapshotFilterInfo();
    public Set<String> soqlTypes = new Set<String>();

    // Get all record type according to metadata item lists passed in constructor
    // Get all record type for all folders also
    // Set up the session
    public ComponentQueryBatch(
        List<String> metaTypeList,
        String session,
        String instance,
        Id snapId,
        DateTime filterDate,
        String filterJSON
    ) {
        System.debug('metaTypeListout---' + metaTypeList);
        if (filterJSON != null && filterJSON != '') {
            FlosumUtils.SnapshotFilterInfo tempFilterInfo = (FlosumUtils.SnapshotFilterInfo) JSON.deserialize(
                filterJSON,
                FlosumUtils.SnapshotFilterInfo.class
            );
            System.debug('metaTypeList---' + metaTypeList);
            System.debug('tempFilterInfo---' + tempFilterInfo);

            if (tempFilterInfo.IsRetrieveStandard) {
                filterInfo.IsRetrieveStandard = true;
            }
            if (tempFilterInfo.isOnlyActiveOmnistudioComponents != null && tempFilterInfo.isOnlyActiveOmnistudioComponents) {
                filterInfo.isOnlyActiveOmnistudioComponents = true;
            }
            if (tempFilterInfo.filterList != null) {
                for (FlosumUtils.SnapshotFilterWraper filterRow : tempFilterInfo.filterList) {
                    if (
                        filterRow != null &&
                        filterRow.value != null &&
                        filterRow.value != '' &&
                        filterRow.operator != null &&
                        filterRow.operator != ''
                    ) {
                        filterInfo.filterList.add(filterRow);
                    }
                }
            }
            if (tempFilterInfo.selectedComponentsName != null) {
                filterInfo.selectedComponentsName = tempFilterInfo.selectedComponentsName;
            }
            if (tempFilterInfo.isNameSpaceSelected != null) {
                if (tempFilterInfo.isNameSpaceSelected) {
                    filterInfo.isNameSpaceSelected = true;
                }
            }
            if (tempFilterInfo.selectedNamespaceSet != null) {
                filterInfo.selectedNamespaceSet.addAll(tempFilterInfo.selectedNamespaceSet);
            }
        }
        List<Snapshot__c> snapLi = new List<Snapshot__c>();
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Snapshot__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Snapshot__c.Last_Modified_In_Days__c.getDescribe()
                }
            }
        );
        snapLi = [SELECT Id, Last_Modified_In_Days__c FROM Snapshot__c WHERE Id = :snapId LIMIT 1];
        if (snapLi.size() == 1) {
            String noteMessage = 'Note:- In the snapshot retrieval process there are two steps, list components of the org and retrieve the content of these components by using Salesforce API.\nIn a few cases, while list components process Flosum get names of few components by the API but in the second process, it doesn\'t get content of few components.\nIt happens in the following cases:\n1)Standard components which are not changed/modified by the user.\n2)Org-wide settings if an object/setting is not active on the Org.\n3)Permission issue, if the auth user does not have access to view the component.\n4)If the component is a part of a salesforce standard feature(Like PersonAccount feature) or etc.';
            retrievalLog += noteMessage + ' \n\n';
            retrievalLog +=
                MetadataUtils.getTimeForLog() +
                ':  Snapshot started at ' +
                MetadataUtils.getTimeForLog() +
                ' for last ' +
                snapLi[0].Last_Modified_In_Days__c +
                ' days.\n';
        }
        this.filterDate = filterDate;
        this.session = session;
        this.instance = instance;
        this.snapId = snapId;
        metadataTypeSet = new Set<String>(metaTypeList);

        fullObjectName = Schema.sObjectType.Metadata_Item__c.getName();
        this.query =
            'select Name, Id from RecordType WHERE Name Not IN:filterSet AND Name IN :metadataTypeSet and SobjectType = \'' +
            String.escapeSingleQuotes(fullObjectName) +
            '\' ORDER By Name';
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                RecordType.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    RecordType.SobjectType.getDescribe()
                }
            }
        );
        for (RecordType rt : [
            SELECT Name, Id
            FROM RecordType
            WHERE Name IN :metadataTypeSet AND SobjectType = :fullObjectName
            LIMIT 1000
        ]) {
            RecordTypeMap.put(rt.Name, rt.Id);
        }
        this.service = MetadataUtils.createService(this.session, this.instance);
    }

    public Database.QueryLocator start(Database.BatchableContext BC) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                RecordType.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    RecordType.SobjectType.getDescribe()
                }
            }
        );
        retrievalLog += MetadataUtils.getTimeForLog() + ':  Apex Job Id: ' + BC.getJobId() + '. \n';
        return Database.getQueryLocator(query);
    }

    // Batch size must be 1
    // Create metadata item list for the snapshot
    public void execute(Database.BatchableContext info, List<sObject> scope) {
        System.debug('ComponentQueryBatch execute');
        if (this.snapId != null && this.session != null && this.instance != null) {
            List<RecordType> typeList = new List<RecordType>();
            typeList = (List<RecordType>) scope;
            if (typeList.size() > 0) {
                try {
                    String MetaDataFolder = '';
                    String logMetaType = typeList[0].Name;
                    retrievalLog += MetadataUtils.getTimeForLog() + ':  Retrieving the list of ' + logMetaType + '.\n';
                    // Metadata_Item__c List to insert record
                    List<Metadata_Item__c> itemsList = new List<Metadata_Item__c>();
                    List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery>();
                    MetadataService.ListMetadataQuery queryLayout = new MetadataService.ListMetadataQuery();
                    //queryLayout.folder = MetaDataFolder;
                    queryLayout.type_x = logMetaType;
                    queries.add(queryLayout);
                    MetadataService.FileProperties[] fileProperties = new List<MetadataService.FileProperties>();
                    if (Test.isRunningTest()) {
                        fileProperties = MetadataUtils.testListMetadata();
                    } else {
                        // query metadata items by callout
                        fileProperties = this.service.listMetadata(queries, FlosumConstants.apiversion);
                    }
                    fileProperties = listMissingComponentsWithCustomLogic(logMetaType, fileProperties, filterInfo.isOnlyActiveOmnistudioComponents);
                    if (fileProperties != null) {
                        for (MetadataService.FileProperties fileProperty : fileProperties) {
                            fileProperty.createdById = null;
                            fileProperty.createdById_type_info = null;
                            fileProperty.createdByName_type_info = null;
                            fileProperty.createdDate_type_info = null;
                            fileProperty.fileName_type_info = null;
                            fileProperty.fullName_type_info = null;
                            fileProperty.id_type_info = null;
                            fileProperty.lastModifiedById_type_info = null;
                            fileProperty.lastModifiedByName_type_info = null;
                            fileProperty.lastModifiedDate_type_info = null;
                            fileProperty.manageableState_type_info = null;
                            fileProperty.namespacePrefix_type_info = null;
                            fileProperty.type_x_type_info = null;
                            fileProperty.apex_schema_type_info = null;
                            fileProperty.field_order_type_info = null;
                        }
                    }
                    // Metadatatype and List of MetadataItems Map
                    if (fileProperties != null) {
                        Set<String> componentNameSet = new Set<String>();
                        //collect MetadataItems for every Metadatatype
                        for (MetadataService.FileProperties fileProperty : fileProperties) {
                            if (fileProperty.type_x == null) {
                                fileProperty.type_x = logMetaType;
                            }
                            if (filterInfo.selectedComponentsName.size() > 0) {
                                if (FlosumConstants.filterName(fileProperty, filterInfo)) {
                                    continue;
                                }
                            }

                            if (
                                !componentNameSet.contains(fileProperty.fullname) &&
                                FlosumConstants.filterFilePropertyItem(fileProperty, filterDate, filterInfo) &&
                                RecordTypeMap.containsKey(fileProperty.type_x)
                            ) {
                                //Modifications in fullName and fileName according to errors we get from salesforce
                                fileProperty = FlosumConstants.fixNamesOfItems(fileProperty);

                                Id typeId = RecordTypeMap.get(fileProperty.type_x);
                                Metadata_Item__c item = new Metadata_Item__c(RecordTypeId = typeId);
                                item.MetaId__c = fileProperty.id;
                                item.Name__c = fileProperty.fullname;
                                item.API_Name__c = fileProperty.fullname;
                                item.Snapshot__c = snapId;
                                item.Label__c = fileProperty.fileName;
                                item.Last_Updated_By__c = fileProperty.lastModifiedByName;
                                item.Last_Modified_Date__c = fileProperty.lastModifiedDate;
                                item.Folder__c = MetaDataFolder;
                                item.Is_Retrieved__c = false;

                                if (MetadataUtils.validateConditionsWithList(filterInfo, item, fileProperty.type_x)) {
                                    if (itemsList.size() < 10000)
                                        itemsList.add(item);
                                    else if (globalItemsList.size() < 9900)
                                        globalItemsList.add(item);
                                    componentNameSet.add(item.API_Name__c);
                                }
                            }
                        }
                        if (itemsList.size() > 0) {
                            //inserting metadataitems list
                            DatabaseUtils.insertRecords(
                                itemsList,
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
                                    Metadata_Item__c.MetaId__c.getDescribe()
                                }
                            );
                        }
                    }
                } catch (Exception e) {
                    // Log the exception and continue
                    if (
                        e.getMessage().containsIgnoreCase('IO Exception: Exceeded max size limit of 12000000') &&
                        (typeList[0].Name == 'Role' ||
                        typeList[0].Name == 'Group')
                    ) {
                        soqlTypes.add(typeList[0].Name);
                    } else {
                        String error =
                            '--- Technical Detail ---\n[1] ' +
                            e.getMessage() +
                            ' \n[2] ' +
                            e.getCause() +
                            ' \n[3] ' +
                            e.getLineNumber();
                        error += '----Exception at query items----';
                        System.debug(error);
                        retrievalLog += MetadataUtils.getTimeForLog() + error + '.\n';
                        retrievalLog +=
                            MetadataUtils.getTimeForLog() +
                            ':  Unable to retrieve the number of components changed for ' +
                            typeList[0].Name +
                            '.\n';
                    }
                }
            }
        } else {
            // session or snapshot not found
            System.abortJob(info.getJobId());
        }
    }

    // Check if metadata records created or not
    // If any record exist process will continue.
    public void finish(Database.BatchableContext BC) {
        if (this.snapId != null && this.session != null && this.instance != null) {
            Set<String> remainingTypes = new Set<String>();
            for (String metaType : filterSet) {
                if (metadataTypeSet.contains(metaType)) {
                    remainingTypes.add(metaType);
                }
            }
            if (soqlTypes.size() > 0) {
                Database.executeBatch(
                    new SOQLQueryBatch(
                        remainingTypes,
                        this.session,
                        this.instance,
                        this.snapId,
                        this.filterDate,
                        filterInfo,
                        soqlTypes
                    ),
                    1
                );
                insertLog(this.snapId);
            } else if (remainingTypes.contains('CustomField')) {
                //if exception of 3mb comes at retrieval of CustomField
                Database.executeBatch(
                    new CustomFieldQueryBatch(
                        remainingTypes,
                        this.session,
                        this.instance,
                        this.snapId,
                        this.filterDate,
                        filterInfo
                    ),
                    2
                );
                insertLog(this.snapId);
            } else if (remainingTypes.size() > 0) {
                Database.executeBatch(
                    new ComponentFolderQueryBatch(
                        remainingTypes,
                        this.session,
                        this.instance,
                        this.snapId,
                        this.filterDate,
                        filterInfo
                    ),
                    1
                );
                insertLog(this.snapId);
            } else {
                //count the metadataitems
                List<Metadata_Item__c> metaList = new List<Metadata_Item__c>();
                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        Metadata_Item__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            Metadata_Item__c.Snapshot__c.getDescribe(),
                            Metadata_Item__c.Name__c.getDescribe(),
                            Metadata_Item__c.API_Name__c.getDescribe(),
                            Metadata_Item__c.Is_Retrieved__c.getDescribe()
                        }
                    }
                );
                metaList = [
                    SELECT Id
                    FROM Metadata_Item__c
                    WHERE
                        Snapshot__c = :this.snapId
                        AND Name__c != NULL
                        AND API_Name__c != NULL
                        AND Is_Retrieved__c = FALSE
                    LIMIT 1
                ];
                //check if snapshot have error at query items
                List<Snapshot__c> snapList = new List<Snapshot__c>();
                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        Snapshot__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            Snapshot__c.Is_Error__c.getDescribe(),
                            Snapshot__c.Apex_Is_Completed__c.getDescribe(),
                            Snapshot__c.Last_Modified_In_Days__c.getDescribe()
                        }
                    }
                );
                snapList = [
                    SELECT Is_Error__c, Apex_Is_Completed__c, Last_Modified_In_Days__c
                    FROM Snapshot__c
                    WHERE Id = :this.snapId
                    LIMIT 1
                ];
                if (snapList.size() == 1) {
                    if (metaList.size() > 0 && !Test.isRunningTest()) {
                        // call retrive batch
                        Database.executeBatch(
                            new SnapshotRetrieveBatch(
                                this.session,
                                this.instance,
                                this.snapId,
                                new Map<String, Integer>()
                            ),
                            1
                        );
                        insertLog(this.snapId);
                    } else {
                        retrievalLog += MetadataUtils.getTimeForLog() + ':  Snapshot completed successfully.\n';
                        retrievalLog +=
                            MetadataUtils.getTimeForLog() +
                            ':  No components are changed in last ' +
                            snapList[0].Last_Modified_In_Days__c +
                            ' days.\n';
                        insertLog(this.snapId);
                        completeApexLog(this.snapId);
                    }
                }
            }
            if (globalItemsList.size() > 0) {
                retrievalLog += MetadataUtils.getTimeForLog() + ':  Saving Component Names.\n';
                DatabaseUtils.insertRecords(
                    globalItemsList,
                    new List<Schema.DescribeFieldResult>{
                        Metadata_Item__c.RecordTypeId.getDescribe(),
                        Metadata_Item__c.Name__c.getDescribe(),
                        Metadata_Item__c.API_Name__c.getDescribe(),
                        Metadata_Item__c.Snapshot__c.getDescribe(),
                        Metadata_Item__c.Label__c.getDescribe(),
                        Metadata_Item__c.Last_Modified_Date__c.getDescribe(),
                        Metadata_Item__c.Last_Updated_By__c.getDescribe(),
                        Metadata_Item__c.Folder__c.getDescribe(),
                        Metadata_Item__c.Is_Retrieved__c.getDescribe()
                    }
                );
            }
        }
    }

    public void completeApexLog(Id snapshotId) {
        List<Metadata_Log__c> logLi = new List<Metadata_Log__c>();
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
        logLi = [
            SELECT Id, Process_Type__c, Job_Completed__c, Status__c, Succeed__c
            FROM Metadata_Log__c
            WHERE
                Snapshot__c = :snapshotId
                AND Process_Type__c = :FlosumConstants.PROCESS_SNAPSHOT_LOG_APEX
                AND Status__c = :FlosumConstants.STATUS_IN_PROGRESS
            LIMIT 1
        ];
        if (logLi.size() == 1) {
            logLi[0].Job_Completed__c = true;
            logLi[0].Status__c = FlosumConstants.STATUS_COMPLETED;
            logLi[0].Succeed__c = true;
            DatabaseUtils.updateRecords(
                logLi,
                new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Job_Completed__c.getDescribe(),
                    Metadata_Log__c.Status__c.getDescribe(),
                    Metadata_Log__c.Succeed__c.getDescribe()
                }
            );
        }
    }

    public void insertLog(Id snapshotId) {
        List<Metadata_Log__c> logLi = new List<Metadata_Log__c>();
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Metadata_Log__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Snapshot__c.getDescribe(),
                    Metadata_Log__c.Process_Type__c.getDescribe()
                },
                Snapshot__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
            }
        );
        logLi = [
            SELECT Id, Snapshot__r.Name
            FROM Metadata_Log__c
            WHERE Snapshot__c = :snapshotId AND Process_Type__c = :FlosumConstants.PROCESS_SNAPSHOT_LOG_APEX
            LIMIT 1
        ];
        if (logLi.size() == 1) {
            List<Attachment> attLi = new List<Attachment>();
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Attachment.Body.getDescribe(),
                        Attachment.Description.getDescribe(),
                        Attachment.ParentId.getDescribe()
                    }
                }
            );
            attLi = [SELECT Id, Body FROM Attachment WHERE Description = 'APEX' AND ParentId = :logLi[0].Id LIMIT 1];
            if (attLi.size() == 1) {
                attLi[0].Body = Blob.valueOf(attLi[0].Body.toString() + retrievalLog);
                DatabaseUtils.updateRecords(
                    attLi,
                    new List<Schema.DescribeFieldResult>{ Attachment.Body.getDescribe() }
                );
            } else {
                Attachment att = new Attachment(ParentId = logLi[0].Id);
                att.Name = logLi[0].Snapshot__r.Name + ' Logfile';
                att.Body = Blob.valueOf(retrievalLog);
                att.Description = 'APEX';
                att.ContentType = 'text/plain';
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
            }
        }
    }

    public List<MetadataService.FileProperties> listMissingComponentsWithCustomLogic(
        String logMetaType,
        List<MetadataService.FileProperties> fileProperties,
        Boolean isOnlyActiveOmnistudioComponents
    ) {
        try {
            if (fileProperties == null) {
                fileProperties = new List<MetadataService.FileProperties>();
            }
            fileProperties = addBotVersions(logMetaType, fileProperties);
            fileProperties = listPersonAccountRecordTypeAndCompactLayouts(logMetaType, fileProperties);
            
            if (FlosumConstants.activeOmnistudioComponentTypes.containsKey(logMetaType) && isOnlyActiveOmnistudioComponents) {
				fileProperties = removeInactiveOmniComponents(logMetaType, fileProperties);                                                 
            }
            
            if (logMetaType == 'StandardValueSet') {
                for (String valueSetName : FlosumConstants.standardValueSet) {
                    MetadataService.FileProperties fileProperty = new MetadataService.FileProperties();
                    fileProperty.fullName = valueSetName;
                    fileProperty.fileName = 'standardValueSets/' + valueSetName + '.standardValueSet';
                    fileProperty.lastModifiedByName = '';
                    fileProperty.lastModifiedDate = DateTime.newInstance(0);
                    fileProperty.type_x = logMetaType;
                    fileProperties.add(fileProperty);
                }
            }
            
            Set<String> listTypeSet = new Set<String>();
            if (logMetaType == 'WaveDataflow') {
                listTypeSet.add('WaveRecipe');
            } else if (logMetaType == 'WaveXmd') {
                listTypeSet.add('WaveDashboard');
                listTypeSet.add('WaveLens');
            } else if (logMetaType == 'Flow') {
                listTypeSet.add('FlowDefinition');
            }
            if (listTypeSet.size() > 0) {
                MetadataService.FileProperties[] fileProperties2 = new List<MetadataService.FileProperties>();
                List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery>();
                for(String qType : listTypeSet) {
                    MetadataService.ListMetadataQuery queryLayout = new MetadataService.ListMetadataQuery();
                    queryLayout.type_x = qType;
                    queries.add(queryLayout);
                }
                if (Test.isRunningTest()) {
                    fileProperties2 = MetadataUtils.testListMetadata();
                } else {
                    // query metadata items by callout
                    fileProperties2 = this.service.listMetadata(queries, FlosumConstants.apiversion);
                }
                Set<String> waveNameSet = new Set<String>();
                for (MetadataService.FileProperties fileProperty : fileProperties) {
                    waveNameSet.add(fileProperty.fullName);
                }
                for (MetadataService.FileProperties fileProperty : fileProperties2) {
                    if (
                        fileProperty != null &&
                        !waveNameSet.contains(fileProperty.fullName)
                    ) {
                        MetadataService.FileProperties dataFlow = new MetadataService.FileProperties();
                        dataFlow.fullName = fileProperty.fullName;
                        dataFlow.type_x = logMetaType;
                        dataFlow.lastModifiedByName = fileProperty.lastModifiedByName;
                        dataFlow.lastModifiedDate = fileProperty.lastModifiedDate;
                        if (logMetaType == 'WaveDataflow')
                            dataFlow.fileName = 'wave/' + fileProperty.fullName + '.wdf';
                        else if (logMetaType == 'WaveXmd')
                            dataFlow.fileName = 'wave/' + fileProperty.fullName + '.xmd';
                        else if (logMetaType == 'Flow')
                            dataFlow.fileName = 'flows/' + fileProperty.fullName + '.flow';
                        fileProperties.add(dataFlow);
                    }
                }
            }
        } catch (Exception ex) {
            String error =
                '--- Technical Detail ---\n[1] ' +
                ex.getMessage() +
                ' \n[2] ' +
                ex.getCause() +
                ' \n[3] ' +
                ex.getLineNumber();
            error += '----Exception at listMissingComponentsWithCustomLogic----';
            retrievalLog += MetadataUtils.getTimeForLog() + error + '.\n';
        }
        return fileProperties;
    }

    public List<MetadataService.FileProperties> listPersonAccountRecordTypeAndCompactLayouts(
        String logMetaType,
        List<MetadataService.FileProperties> fileProperties
    ) {
        //List RecordType with tooling API
        Map<String, String> personAccountMap = new Map<String, String>();
        try {
            String query;
            if (logMetaType == 'RecordType') {
                query = 'SELECT Id,DeveloperName,IsPersonType,NamespacePrefix FROM RecordType WHERE SobjectType = \'Account\'';
                String endpoint =
                    this.instance +
                    '/services/data/v52.0/query/?q=' +
                    EncodingUtil.urlEncode(query, 'UTF-8');
                HttpRequest req = new HttpRequest();
                req.setHeader('Authorization', 'Bearer ' + this.session);
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
            } else if (logMetaType == 'CompactLayout') {
                query = 'SELECT Id,fullName FROM CompactLayout WHERE SObjectType = \'Account\'';
                String endpoint =
                    this.instance +
                    '/services/data/v34.0/tooling' +
                    '/query/?q=' +
                    EncodingUtil.urlEncode(query, 'UTF-8');
                HttpRequest req = new HttpRequest();
                req.setHeader('Authorization', 'Bearer ' + this.session);
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
        } catch (Exception ex) {
            String error =
                '--- Technical Detail ---\n[1] ' +
                ex.getMessage() +
                ' \n[2] ' +
                ex.getCause() +
                ' \n[3] ' +
                ex.getLineNumber();
            error += '----Exception at tooling query----';
            retrievalLog += MetadataUtils.getTimeForLog() + error + '.\n';
        }
        if (personAccountMap.size() > 0) {
            for (MetadataService.FileProperties fileProperty : fileProperties) {
                if (fileProperty != null && fileProperty.Id != null && personAccountMap.containsKey(fileProperty.Id)) {
                    String recordTypeFullName = personAccountMap.get(fileProperty.Id);
                    if (recordTypeFullName.startsWithIgnoreCase('PersonAccount.')) {
                        fileProperty.fullName = recordTypeFullName;
                        fileProperty.fileName = 'objects/PersonAccount.object';
                    }
                }
            }
        }
        return fileProperties;
    }

    public List<MetadataService.FileProperties> addBotVersions(
        String logMetaType,
        List<MetadataService.FileProperties> fileProperties
    ) {
        if (logMetaType != 'BotVersion' || (fileProperties != null && fileProperties.size() != 0)) {
            return fileProperties;
        }

        List<MetadataService.FileProperties> botVersions = new List<MetadataService.FileProperties>();

        String query =
            'SELECT Id, BotDefinitionId, BotDefinition.DeveloperName, DeveloperName, ' +
            'VersionNumber, Status, LastModifiedBy.Name, LastModifiedDate, CreatedDate, CreatedBy.Name ' +
            'FROM BotVersion';
        String endpoint = this.instance + '/services/data/v52.0/query/?q=' + EncodingUtil.urlEncode(query, 'UTF-8');
        HttpRequest request = new HttpRequest();
        request.setHeader('Authorization', 'Bearer ' + this.session);
        request.setHeader('Content-Type', 'application/json');
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setTimeout(120000);

        Http httpRequest = new Http();
        HttpResponse requestResult = httpRequest.send(request);

        if (requestResult.getStatusCode() != 200) {
            throw new FlosumException(requestResult.getBody());
        }

        //parsing resoponse and get the fullname of botVersion
        BotVersionWrapper resultWrapper = (BotVersionWrapper) JSON.deserialize(
            requestResult.getBody(),
            BotVersionWrapper.class
        );

        for (BotVersionRecord botVersion : resultWrapper.records) {
            MetadataService.FileProperties fileProperty = new MetadataService.FileProperties();
            fileProperty.fullName = botVersion.BotDefinition.DeveloperName + '.' + botVersion.DeveloperName;
            fileProperty.fileName = 'bots/' + botVersion.BotDefinition.DeveloperName + '.bot';
            fileProperty.lastModifiedByName = botVersion.LastModifiedBy.Name;
            fileProperty.lastModifiedDate = botVersion.LastModifiedDate;
            fileProperty.type_x = 'BotVersion';
            botVersions.add(fileProperty);
        }

        return botVersions;
    }
    
    public List<MetadataService.FileProperties> removeInactiveOmniComponents(
        String logMetaType,
        List<MetadataService.FileProperties> fileProperties
    ) {
        if (fileProperties.isEmpty()) {
            return fileProperties;
        }

        String omniCustomRecordType = FlosumConstants.activeOmnistudioComponentTypes.get(logMetaType).nameObject;

        List<MetadataService.FileProperties> activeOmnistudioComponents = new List<MetadataService.FileProperties>();

		String queryTemplate = 'SELECT Id, Name, IsActive, Uniquename, LastModifiedBy.Name, LastModifiedDate FROM {0} WHERE IsActive = true';

        String query = String.format(queryTemplate, new List<String>{ omniCustomRecordType });
 
        String endpointTemplate = '{0}/services/data/v{1}.0/query/?q={2}';

        String endpoint = String.format(
            endpointTemplate,
            new List<String>{ this.instance, String.valueof(FlosumConstants.apiversion), EncodingUtil.urlEncode(query, 'UTF-8') }
        );

        HttpRequest request = new HttpRequest();
        request.setHeader('Authorization', 'Bearer ' + this.session);
        request.setHeader('Content-Type', 'application/json');
        request.setEndpoint(endpoint);
        request.setMethod('GET');
        request.setTimeout(120000);
        
        Http httpRequest = new Http();
        HttpResponse requestResult = httpRequest.send(request);

        if (requestResult.getStatusCode() != 200) {
            throw new FlosumException(requestResult.getBody());
        }

        OmniComponentWrapper resultWrapper = (OmniComponentWrapper) JSON.deserialize(
            requestResult.getBody(),
            OmniComponentWrapper.class
        );
        
        String folderName = FlosumConstants.activeOmnistudioComponentTypes.get(logMetaType).folderName;
        String extension = FlosumConstants.activeOmnistudioComponentTypes.get(logMetaType).extension;

        for (OmniComponentRecord omniComponent : resultWrapper.records) {
            MetadataService.FileProperties fileProperty = new MetadataService.FileProperties();
            fileProperty.fullName = omniComponent.UniqueName;
            fileProperty.fileName = folderName + '/' + omniComponent.UniqueName + extension;
            fileProperty.lastModifiedByName = omniComponent.LastModifiedBy.Name;
            fileProperty.lastModifiedDate = omniComponent.LastModifiedDate;
            fileProperty.type_x = logMetaType;
            activeOmnistudioComponents.add(fileProperty);
        }

        return activeOmnistudioComponents;
    }
    
    public class BotVersionWrapper {
        public Integer totalSize { get; set; }
        public Boolean done { get; set; }
        public List<BotVersionRecord> records { get; set; }
    }
    
    public class BotVersionRecord {
        public String Id { get; set; }
        public String BotDefinitionId { get; set; }
        public BotDefinitionAttributes BotDefinition { get; set; }
        public String DeveloperName { get; set; }
        public Integer VersionNumber { get; set; }
        public String Status { get; set; }
        public UserAttributes LastModifiedBy { get; set; }
        public DateTime LastModifiedDate { get; set; }
        public DateTime CreatedDate { get; set; }
        public UserAttributes CreatedBy { get; set; }
    }
    
    public class BotDefinitionAttributes {
        public BotDefinitionAttributes attributes { get; set; }
        public String DeveloperName { get; set; }
    }

    public class UserAttributes {
        public UserAttributes attributes { get; set; }
        public String Name { get; set; }
    }
    
    public class OmniComponentWrapper {
        public Integer totalSize { get; set; }
        public Boolean done { get; set; }
        public List<OmniComponentRecord> records { get; set; }
    }
    
    public class OmniComponentRecord {
        public String Id { get; set; }
        public Attributes componentsDefinition { get; set; }
        public String Name { get; set; }
        public Boolean IsActive { get; set; }
        public String UniqueName { get; set; }
        public UserAttributes LastModifiedBy { get; set; }
        public DateTime LastModifiedDate { get; set; }
    }
    
    public class Attributes {
        public String Url { get; set; }
        public String Type { get; set; }
    }
}