public with sharing class TrackingService {
    public static final String TRACKING_SCHEDULER_NAME = 'Tracking Automation';
    public static final String STORAGE_LIMIT_EXCEEDED = 'STORAGE LIMIT EXCEEDED';
    public static final String PROCESS_TYPE_RETRIEVE_ORGANIZATION = 'Tracking Organization - Retrieve';
    public static final String PROCESS_TYPE_RETRIEVE_MANUALLY_ORGANIZATION = 'Tracking Organization - Retrieve Manually';
    public static final String TRACKING_ORGANIZATION_LOG_NAME = 'Tracking Organization Log';
    public static final String QUERY_ORG_FIELD_ID_IN_ORG_COMPONENT = 'SELECT+Id,+DeveloperName,+EntityDefinitionId+FROM+CustomField+WHERE+DeveloperName+=\'OrganisationName\'';

    public static String QUERY_SOURCE_MEMBER = 'SELECT+Id,+MemberIdOrName,+ChangedBy,+IsNameObsolete,+IsNewMember,+MemberName,+MemberType,+RevisionCounter,+LastModifiedDate,+LastModifiedBy.Name+FROM+SourceMember+WHERE+MemberType+!=+\'LightningComponentResource\'';
    public static final String QUERY_COUNT_SOURCE_MEMBER = 'SELECT+COUNT(Id)+SourceMemberSize+FROM+SourceMember+WHERE+MemberType+!=+\'LightningComponentResource\'';
    public static final String QUERY_SIZE_STATIC_RESOURCE = 'SELECT+Id,+BodyLength+FROM+StaticResource';

    public static final Set<String> TYPES_LARGE_WEIGHS_SET = new Set<String>{
        'Layout',
        'Profile',
        'StaticResource',
        'Translations',
        'CustomObjectTranslation'
    };

    public static String ExternalJobURL = getExternalURL() + '/job/';

    public static String getExternalURL() {
        Credentials__c creds = Credentials__c.getOrgDefaults();
        if (creds != null && creds.Pipeline_Agent_URL__c != null) {
            return creds.Pipeline_Agent_URL__c + '/api/v1/tracking-metadata';
        }
        return null;
    }

    public static Boolean isExternalRetrievalEnabled() {
        Credentials__c creds = Credentials__c.getOrgDefaults();
        if (
            creds != null &&
            creds.Retrieval_Method__c == ExternalSnapshotService.ExternalRetrievalMethod &&
            getExternalURL() != null
        ) {
            return true;
        }
        return false;
    }

    public static String makeApiCall(String endpoint, String bodyDetail, String methodType) {
        HttpRequest req = new HttpRequest();
        req.setHeader('Content-Type', 'application/json');
        req.setEndpoint(endpoint);
        req.setMethod(methodType);
        req.setTimeout(120000);
        if (bodyDetail != null) {
            req.setBody(bodyDetail);
        }
        Http httpreq = new Http();
        HttpResponse res = httpreq.send(req);
        if (res.getStatusCode() == 201) {
            return res.getBody();
        }
        throw new FlosumException(res.getStatusCode() + ': ' + res.getBody());
    }

    public static String startAgentJob(String body) {
        String endpoint = ExternalJobURL;
        String response = makeApiCall(endpoint, body, 'POST');
        AgentJobWrapper responseBody = (AgentJobWrapper) JSON.deserialize(response, AgentJobWrapper.class);
        return responseBody.jobId;
    }

    public static Metadata_Log__c createLog(
        String organizationId,
        String trackingSettingId,
        String processType,
        String logName
    ) {
        Metadata_Log__c metadataLog = new Metadata_Log__c();
        metadataLog.Status__c = FlosumConstants.STATUS_IN_PROGRESS;
        metadataLog.Start_Date__c = Datetime.now();
        metadataLog.Process_Type__c = processType;
        metadataLog.Organisation__c = organizationId;
        metadataLog.Tracking_Setting__c = trackingSettingId;
        metadataLog.Start_Date__c = Datetime.now();

        DatabaseUtils.insertRecord(
            metadataLog,
            new List<DescribeFieldResult>{
                Metadata_Log__c.Organisation__c.getDescribe(),
                Metadata_Log__c.Status__c.getDescribe(),
                Metadata_Log__c.Start_Date__c.getDescribe(),
                Metadata_Log__c.Process_Type__c.getDescribe()
            }
        );

        Attachment logAttachment = new Attachment();
        logAttachment.ContentType = 'text/plain';
        logAttachment.Name = logName;
        logAttachment.Body = Blob.valueOf('');
        logAttachment.ParentId = metadataLog.Id;

        DatabaseUtils.insertRecord(
            logAttachment,
            new List<DescribeFieldResult>{
                Attachment.ContentType.getDescribe(),
                Attachment.Name.getDescribe(),
                Attachment.Body.getDescribe(),
                Attachment.ParentId.getDescribe()
            }
        );

        return metadataLog;
    }

    public static List<RetrieveComponentWrapper> checkDependency(
        String accessToken,
        String instanceUrl,
        RetrieveComponentWrapper retrieveComponentWrapper
    ) {
        //if you will add new type, and you will use something other than retrieveComponentWrapper.type,
        //please add this type to typeNeedCheckDependencyInLoopSet
        List<RetrieveComponentWrapper> dependenciesComponentWrapperList = new List<RetrieveComponentWrapper>();
        if (retrieveComponentWrapper.type == FlosumConstants.META_Profile) {
            for (String metaPermissionType : FlosumConstants.MetaTypesForPermissionSet) {
                dependenciesComponentWrapperList.add(
                    new RetrieveComponentWrapper(metaPermissionType, new List<String>{ FlosumConstants.META_WILD_CARD })
                );
            }

            MetadataService.MetadataPort service = MetadataUtils.createService(accessToken, instanceUrl);
            List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery>();
            MetadataService.ListMetadataQuery queryLayout = new MetadataService.ListMetadataQuery();
            queryLayout.folder = '';
            queryLayout.type_x = 'CustomObject';
            queries.add(queryLayout);
            MetadataService.FileProperties[] fileProperties = new List<MetadataService.FileProperties>();
            fileProperties = service.listMetadata(queries, FlosumConstants.getMetadataAPIVersion());

            if (!fileProperties.isEmpty()) {
                RetrieveComponentWrapper dependency = new RetrieveComponentWrapper();
                dependency.isDependency = true;
                dependency.type = 'CustomObject';
                dependency.componentList = new List<TrackingService.SourceMemberWrapper>();
                for (MetadataService.FileProperties fileProperty : fileProperties) {
                    dependency.componentList.add(new SourceMemberWrapper(fileProperty.fullName));
                }
                dependenciesComponentWrapperList.add(dependency);
            }
        } else if (retrieveComponentWrapper.type == 'CustomObjectTranslation') {
            Set<String> objectNames = new Set<String>();
            Set<String> layoutNames = new Set<String>();
            Set<String> quickActionNames = new Set<String>();

            RetrieveComponentWrapper dependencyCustomObject = new RetrieveComponentWrapper();
            dependencyCustomObject.type = 'CustomObject';
            dependencyCustomObject.isDependency = true;
            dependencyCustomObject.componentList = new List<TrackingService.SourceMemberWrapper>();
            RetrieveComponentWrapper dependencyWorkflow = new RetrieveComponentWrapper();
            dependencyWorkflow.type = 'Workflow';
            dependencyWorkflow.isDependency = true;
            dependencyWorkflow.componentList = new List<TrackingService.SourceMemberWrapper>();

            for (SourceMemberWrapper sourceMemberWrapper : retrieveComponentWrapper.componentList) {
                String parentObjectName = sourceMemberWrapper.componentName.substring(
                    0,
                    sourceMemberWrapper.componentName.indexOf('-')
                );
                dependencyCustomObject.componentList.add(new SourceMemberWrapper(parentObjectName));
                dependencyWorkflow.componentList.add(new SourceMemberWrapper(parentObjectName));
            }

            dependenciesComponentWrapperList.add(dependencyCustomObject);
            dependenciesComponentWrapperList.add(dependencyWorkflow);

            List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery>();
            MetadataService.ListMetadataQuery queryLayout = new MetadataService.ListMetadataQuery();
            queryLayout.folder = '';
            queryLayout.type_x = 'Layout';
            queries.add(queryLayout);
            queryLayout = new MetadataService.ListMetadataQuery();
            queryLayout.folder = '';
            queryLayout.type_x = 'QuickAction';
            queries.add(queryLayout);
            MetadataService.MetadataPort service = MetadataUtils.createService(accessToken, instanceUrl);
            MetadataService.FileProperties[] fileProperties = service.listMetadata(
                queries,
                FlosumConstants.getMetadataAPIVersion()
            );
            if (fileProperties != null && !fileProperties.isEmpty()) {
                for (MetadataService.FileProperties fileProperty : fileProperties) {
                    if (fileProperty.fullName != null) {
                        if (fileProperty.type_x == 'Layout') {
                            fileProperty = FlosumConstants.fixNamesOfItems(fileProperty);
                            String layoutObjectName = fileProperty.fullName.substring(
                                0,
                                fileProperty.fullName.indexOf('-')
                            );
                            if (objectNames.contains(layoutObjectName)) {
                                layoutNames.add(fileProperty.fullName);
                            }
                        } else if (fileProperty.type_x == 'QuickAction') {
                            fileProperty = FlosumConstants.fixNamesOfItems(fileProperty);
                            if (fileProperty.fullName.indexOf('.') > -1) {
                                String quickActionObjectName = fileProperty.fullName.substring(
                                    0,
                                    fileProperty.fullName.indexOf('.')
                                );
                                if (objectNames.contains(quickActionObjectName)) {
                                    quickActionNames.add(fileProperty.fullName);
                                }
                            } else {
                                quickActionNames.add(fileProperty.fullName);
                            }
                        }
                    }
                }
            }
            if (!layoutNames.isEmpty()) {
                dependenciesComponentWrapperList.add(new RetrieveComponentWrapper('Layout', layoutNames));
            }
            if (!quickActionNames.isEmpty()) {
                dependenciesComponentWrapperList.add(new RetrieveComponentWrapper('QuickAction', quickActionNames));
            }
        } else if (retrieveComponentWrapper.type == 'Translations') {
            Set<String> customAppNames = new Set<String>();
            Set<String> customPageWebLinkNames = new Set<String>();
            Set<String> customTabNames = new Set<String>();
            Set<String> quickActionNames = new Set<String>();
            Set<String> reportTypeNames = new Set<String>();

            dependenciesComponentWrapperList.add(new RetrieveComponentWrapper('CustomLabels', new List<String>{ '*' }));
            dependenciesComponentWrapperList.add(new RetrieveComponentWrapper('Scontrol', new List<String>{ '*' }));

            List<MetadataService.ListMetadataQuery> queries = new List<MetadataService.ListMetadataQuery>();
            MetadataService.ListMetadataQuery queryLayout = new MetadataService.ListMetadataQuery();
            queryLayout.folder = '';
            queryLayout.type_x = 'CustomApplication';
            queries.add(queryLayout);
            queryLayout = new MetadataService.ListMetadataQuery();
            queryLayout.folder = '';
            queryLayout.type_x = 'CustomPageWebLink';
            queries.add(queryLayout);
            queryLayout = new MetadataService.ListMetadataQuery();
            queryLayout.folder = '';
            queryLayout.type_x = 'CustomTab';
            queries.add(queryLayout);
            MetadataService.MetadataPort service = MetadataUtils.createService(accessToken, instanceUrl);
            MetadataService.FileProperties[] fileProperties = service.listMetadata(
                queries,
                FlosumConstants.getMetadataAPIVersion()
            );
            if (fileProperties != null) {
                for (MetadataService.FileProperties fileProperty : fileProperties) {
                    if (fileProperty.fullName != null) {
                        if (fileProperty.type_x == 'CustomApplication') {
                            customAppNames.add(fileProperty.fullName);
                        } else if (fileProperty.type_x == 'CustomPageWebLink') {
                            customPageWebLinkNames.add(fileProperty.fullName);
                        } else if (fileProperty.type_x == 'CustomTab') {
                            customTabNames.add(fileProperty.fullName);
                        }
                    }
                }
            }

            queries = new List<MetadataService.ListMetadataQuery>();
            queryLayout = new MetadataService.ListMetadataQuery();
            queryLayout.folder = '';
            queryLayout.type_x = 'QuickAction';
            queries.add(queryLayout);
            queryLayout = new MetadataService.ListMetadataQuery();
            queryLayout.folder = '';
            queryLayout.type_x = 'ReportType';
            queries.add(queryLayout);

            fileProperties = service.listMetadata(queries, FlosumConstants.getMetadataAPIVersion());
            if (fileProperties != null) {
                for (MetadataService.FileProperties fileProperty : fileProperties) {
                    if (fileProperty.fullName != null) {
                        if (fileProperty.type_x == 'QuickAction') {
                            quickActionNames.add(fileProperty.fullName);
                        } else if (fileProperty.type_x == 'ReportType') {
                            reportTypeNames.add(fileProperty.fullName);
                        }
                    }
                }
            }

            if (!customAppNames.isEmpty()) {
                dependenciesComponentWrapperList.add(new RetrieveComponentWrapper('Scontrol', customAppNames));
            }
            if (!customPageWebLinkNames.isEmpty()) {
                dependenciesComponentWrapperList.add(
                    new RetrieveComponentWrapper('CustomPageWebLink', customPageWebLinkNames)
                );
            }
            if (!customTabNames.isEmpty()) {
                dependenciesComponentWrapperList.add(new RetrieveComponentWrapper('CustomTab', customTabNames));
            }
            if (!quickActionNames.isEmpty()) {
                dependenciesComponentWrapperList.add(new RetrieveComponentWrapper('QuickAction', quickActionNames));
            }
            if (!reportTypeNames.isEmpty()) {
                dependenciesComponentWrapperList.add(new RetrieveComponentWrapper('ReportType', reportTypeNames));
            }
        }
        return dependenciesComponentWrapperList;
    }

    public static List<String> makeRequestRetrieve(
        String accessToken,
        String instanceUrl,
        List<RetrieveComponentWrapper> retrieveComponentWrapperList
    ) {
        List<String> asyncJobList = new List<String>();

        Set<String> typeNeedCheckDependencyInLoopSet = new Set<String>{ 'CustomObjectTranslation' };
        Map<String, List<RetrieveComponentWrapper>> retrieveComponentWrapperDependencyMap = new Map<String, List<TrackingService.RetrieveComponentWrapper>>();
        for (RetrieveComponentWrapper retrieveComponentWrapper : retrieveComponentWrapperList) {
            Boolean isCanCheckDependency =
                !typeNeedCheckDependencyInLoopSet.contains(retrieveComponentWrapper.type) &&
                !retrieveComponentWrapperDependencyMap.containsKey(retrieveComponentWrapper.type);
            if (isCanCheckDependency) {
                retrieveComponentWrapperDependencyMap.put(
                    retrieveComponentWrapper.type,
                    checkDependency(accessToken, instanceUrl, retrieveComponentWrapper)
                );
            }
        }

        for (RetrieveComponentWrapper retrieveComponentWrapper : retrieveComponentWrapperList) {
            Set<String> componentNameSet = new Set<String>();
            for (SourceMemberWrapper sourceMemberWrapper : retrieveComponentWrapper.componentList) {
                if (!sourceMemberWrapper.isDeleted) {
                    componentNameSet.add(sourceMemberWrapper.componentName);
                }
            }
            if (!componentNameSet.isEmpty()) {
                List<MetadataService.PackageTypeMembers> packageTypeMemberList = new List<MetadataService.PackageTypeMembers>();
                retrieveComponentWrapper.dependencyList = typeNeedCheckDependencyInLoopSet.contains(
                        retrieveComponentWrapper.type
                    )
                    ? checkDependency(accessToken, instanceUrl, retrieveComponentWrapper)
                    : retrieveComponentWrapperDependencyMap.get(retrieveComponentWrapper.type);

                MetadataService.PackageTypeMembers packageType = new MetadataService.PackageTypeMembers();
                if (FlosumConstants.metadataFolderMap.containsKey(retrieveComponentWrapper.type)) {
                    packageType.name = FlosumConstants.metadataFolderMap.get(retrieveComponentWrapper.type);
                } else {
                    packageType.name = retrieveComponentWrapper.type;
                }
                packageType.members = new List<String>(componentNameSet);
                packageTypeMemberList.add(packageType);

                if (!retrieveComponentWrapper.dependencyList.isEmpty()) {
                    for (RetrieveComponentWrapper dependency : retrieveComponentWrapper.dependencyList) {
                        MetadataService.PackageTypeMembers dependencyPackageType = new MetadataService.PackageTypeMembers();
                        if (FlosumConstants.metadataFolderMap.containsKey(dependency.type)) {
                            dependencyPackageType.name = FlosumConstants.metadataFolderMap.get(dependency.type);
                        } else {
                            dependencyPackageType.name = dependency.type;
                        }

                        for (SourceMemberWrapper sourceMemberWrapper : dependency.componentList) {
                            componentNameSet.add(sourceMemberWrapper.componentName);
                        }
                        dependencyPackageType.members = new List<String>(componentNameSet);
                        packageTypeMemberList.add(dependencyPackageType);
                    }
                }

                MetadataService.MetadataPort service = MetadataUtils.createService(accessToken, instanceUrl);
                MetadataService.RetrieveRequest retrieveRequest = new MetadataService.RetrieveRequest();
                retrieveRequest.apiVersion = FlosumConstants.getMetadataAPIVersion();
                retrieveRequest.packageNames = null;
                retrieveRequest.singlePackage = true;
                retrieveRequest.specificFiles = null;
                retrieveRequest.unpackaged = new MetadataService.Package_x();
                retrieveRequest.unpackaged.types = packageTypeMemberList;

                if (!Test.isRunningTest()) {
                    MetadataService.AsyncResult asyncResult = service.retrieve_x(retrieveRequest);
                    if (
                        retrieveComponentWrapper.isDependency == null ||
                        (retrieveComponentWrapper.isDependency != null && !retrieveComponentWrapper.isDependency)
                    ) {
                        asyncJobList.add(asyncResult.id + '#' + retrieveComponentWrapper.type);
                        for (SourceMemberWrapper sourceMemberWrapper : retrieveComponentWrapper.componentList) {
                            if (!sourceMemberWrapper.isDeleted) {
                                sourceMemberWrapper.asyncJobId = asyncResult.id;
                            }
                        }
                    }
                } else {
                    asyncJobList.add(TrackingOrganizationControllerTest.ASYNC_JOB);
                }
            }
        }
        return asyncJobList;
    }

    public static AsyncJobIdAndOrgComponentListsWrapper makeLimitMetadataRequest(
        String accessToken,
        String instanceUrl,
        List<String> orgComponentIdSet,
        Logger logger
    ) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Org_Component__c.Name__c.getDescribe(),
                    Org_Component__c.Component_Type__c.getDescribe(),
                    Org_Component__c.Revision_Counter__c.getDescribe(),
                    Org_Component__c.Is_Deleted__c.getDescribe(),
                    Org_Component__c.Last_Updated_By__c.getDescribe(),
                    Org_Component__c.Last_Modified_Date__c.getDescribe(),
                    Org_Component__c.Status__c.getDescribe(),
                    Org_Component__c.Source_Member_Id__c.getDescribe(),
                    Org_Component__c.Name.getDescribe()
                }
            }
        );

        List<Org_Component__c> orgComponentList = [
            SELECT
                Name__c,
                Component_Type__c,
                Revision_Counter__c,
                Is_Deleted__c,
                Last_Updated_By__c,
                Last_Modified_Date__c,
                Name,
                Status__c,
                Source_Member_Id__c
            FROM Org_Component__c
            WHERE Id IN :orgComponentIdSet
        ];

        List<RetrieveComponentWrapper> allRetrieveComponentWrapperList = convertToRetrieveComponentWrapper(
            orgComponentList
        );

        List<RetrieveComponentWrapper> firstRetrieveComponentWrapperList = new List<TrackingService.RetrieveComponentWrapper>();
        List<RetrieveComponentWrapper> secondRetrieveComponentWrapperList = new List<TrackingService.RetrieveComponentWrapper>();

        Integer fc = 0, sc = 0;
        for (RetrieveComponentWrapper allRetrieveComponentWrapper : allRetrieveComponentWrapperList) {
            RetrieveComponentWrapper firstRetrieveComponentWrapper = new RetrieveComponentWrapper();
            RetrieveComponentWrapper secondRetrieveComponentWrapper = new RetrieveComponentWrapper();
            firstRetrieveComponentWrapper.type = allRetrieveComponentWrapper.type;
            secondRetrieveComponentWrapper.type = allRetrieveComponentWrapper.type;
            firstRetrieveComponentWrapper.componentList = new List<TrackingService.SourceMemberWrapper>();
            secondRetrieveComponentWrapper.componentList = new List<TrackingService.SourceMemberWrapper>();

            Integer count = 0;
            for (SourceMemberWrapper sourceMemberWrapper : allRetrieveComponentWrapper.componentList) {
                if (count < allRetrieveComponentWrapper.componentList.size() / 2) {
                    firstRetrieveComponentWrapper.componentList.add(sourceMemberWrapper);
                    fc++;
                } else {
                    sc++;
                    secondRetrieveComponentWrapper.componentList.add(sourceMemberWrapper);
                }
                count++;
            }
            firstRetrieveComponentWrapperList.add(firstRetrieveComponentWrapper);
            secondRetrieveComponentWrapperList.add(secondRetrieveComponentWrapper);
        }

        List<String> asyncJobList = new List<String>();
        List<String> firstAsyncJobList = makeRequestRetrieve(
            accessToken,
            instanceUrl,
            firstRetrieveComponentWrapperList
        );
        List<String> secondAsyncJobList = makeRequestRetrieve(
            accessToken,
            instanceUrl,
            secondRetrieveComponentWrapperList
        );

        for (String asyncJob : firstAsyncJobList) {
            List<String> jobData = asyncJob.split('#');
            String jobId = jobData.get(0);
            String type = jobData.get(1);

            for (RetrieveComponentWrapper retrieveComponentWrapper : firstRetrieveComponentWrapperList) {
                if (type == retrieveComponentWrapper.type) {
                    for (SourceMemberWrapper sourceMemberWrapper : retrieveComponentWrapper.componentList) {
                        for (Org_Component__c orgComponent : orgComponentList) {
                            if (sourceMemberWrapper.id == orgComponent.Id) {
                                orgComponent.Async_Job_Id__c = jobId;
                            }
                        }
                    }
                }
            }
        }

        for (String asyncJob : secondAsyncJobList) {
            List<String> jobData = asyncJob.split('#');
            String jobId = jobData.get(0);
            String type = jobData.get(1);

            for (RetrieveComponentWrapper retrieveComponentWrapper : secondRetrieveComponentWrapperList) {
                if (type == retrieveComponentWrapper.type) {
                    for (SourceMemberWrapper sourceMemberWrapper : retrieveComponentWrapper.componentList) {
                        for (Org_Component__c orgComponent : orgComponentList) {
                            if (sourceMemberWrapper.id == orgComponent.Id) {
                                orgComponent.Async_Job_Id__c = jobId;
                            }
                        }
                    }
                }
            }
        }
        asyncJobList.addAll(firstAsyncJobList);
        asyncJobList.addAll(secondAsyncJobList);

        AsyncJobIdAndOrgComponentListsWrapper resultWrapper = new AsyncJobIdAndOrgComponentListsWrapper();
        resultWrapper.orgComponentList = orgComponentList;
        resultWrapper.asyncJobList = asyncJobList;

        return resultWrapper;
    }

    public static ApexRestResponseWrapper callSourceMemberResponse(String accessToken, String endpoint) {
        HttpResponse httpResponse = callRequest(accessToken, endpoint);
        if (httpResponse.getStatusCode() == 200) {
            TrackingService.ApexRestResponseWrapper apexRestResponseWrapper = (TrackingService.ApexRestResponseWrapper) JSON.deserialize(
                httpResponse.getBody(),
                TrackingService.ApexRestResponseWrapper.class
            );
            return apexRestResponseWrapper;
        } else {
            throw new FlosumException(httpResponse.getBody());
        }
    }

    public static SourceMemberPacksWrapper callSourceMemberRecords(
        String trackingSettingId,
        String accessToken,
        String endpoint
    ) {
        HttpResponse httpResponse = callRequest(accessToken, endpoint);
        if (httpResponse.getStatusCode() == 200) {
            TrackingService.ApexRestResponseWrapper apexRestResponseWrapper = (TrackingService.ApexRestResponseWrapper) JSON.deserialize(
                httpResponse.getBody(),
                TrackingService.ApexRestResponseWrapper.class
            );
            if (apexRestResponseWrapper.records != null && !apexRestResponseWrapper.records.isEmpty()) {
                List<TrackingService.SourceMemberWrapper> sourceMemberWrapperList = convertSourceMembers(
                    apexRestResponseWrapper.records
                );
                sourceMemberWrapperList = removeComponentsThatCannotBeRetrieved(sourceMemberWrapperList);
                List<TrackingService.SourceMemberWrapper> changedSourceMemberWrapperList = new List<TrackingService.SourceMemberWrapper>();
                List<TrackingService.SourceMemberWrapper> tooLargeSourceMemberWrapperList = new List<TrackingService.SourceMemberWrapper>();
                String lastId = sourceMemberWrapperList.get(sourceMemberWrapperList.size() - 1).memberId;

                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            Org_Component__c.Name.getDescribe(),
                            Org_Component__c.Name__c.getDescribe(),
                            Org_Component__c.Component_Type__c.getDescribe(),
                            Org_Component__c.Revision_Counter__c.getDescribe(),
                            Org_Component__c.Is_Processed__c.getDescribe(),
                            Org_Component__c.Status__c.getDescribe()
                        }
                    }
                );

                List<Org_Component__c> orgComponentList = [
                    SELECT Name__c, Component_Type__c, Revision_Counter__c, Is_Processed__c, Status__c
                    FROM Org_Component__c
                    WHERE Tracking_Setting__c = :trackingSettingId
                ];

                Map<String, Org_Component__c> NameSourceMemberMap = new Map<String, Org_Component__c>();
                for (Org_Component__c orgComponent : orgComponentList) {
                    NameSourceMemberMap.put(orgComponent.Name__c + '#' + orgComponent.Component_Type__c, orgComponent);
                }

                for (TrackingService.SourceMemberWrapper sourceMemberWrapper : sourceMemberWrapperList) {
                    if (
                        NameSourceMemberMap.containsKey(
                            sourceMemberWrapper.componentName +
                            '#' +
                            sourceMemberWrapper.componentType
                        )
                    ) {
                        Org_Component__c sourceMember = NameSourceMemberMap.get(
                            sourceMemberWrapper.componentName +
                            '#' +
                            sourceMemberWrapper.componentType
                        );
                        sourceMemberWrapper.sourceMemberId = NameSourceMemberMap.get(
                                sourceMemberWrapper.componentName +
                                '#' +
                                sourceMemberWrapper.componentType
                            )
                            .Id;
                        if (sourceMember.Revision_Counter__c != sourceMemberWrapper.revisionCounter) {
                            changedSourceMemberWrapperList.add(sourceMemberWrapper);
                        } else if (sourceMember.Status__c == 'Too Large') {
                            tooLargeSourceMemberWrapperList.add(sourceMemberWrapper);
                        }
                    } else {
                        changedSourceMemberWrapperList.add(sourceMemberWrapper);
                    }
                }

                SourceMemberPacksWrapper packsWrapper = new SourceMemberPacksWrapper(
                    changedSourceMemberWrapperList,
                    tooLargeSourceMemberWrapperList,
                    apexRestResponseWrapper.nextRecordsUrl,
                    lastId
                );
                return packsWrapper;
            } else {
                return new SourceMemberPacksWrapper(
                    new List<TrackingService.SourceMemberWrapper>(),
                    new List<TrackingService.SourceMemberWrapper>()
                );
            }
        } else {
            throw new FlosumException(httpResponse.getBody());
        }
    }

    public static List<TrackingService.SourceMemberWrapper> removeComponentsThatCannotBeRetrieved(
        List<TrackingService.SourceMemberWrapper> sourceMemberWrapperList
    ) {
        List<TrackingService.SourceMemberWrapper> filteredSourceMemberWrapperList = new List<TrackingService.SourceMemberWrapper>();

        for (SourceMemberWrapper sourceMemberWrapper : sourceMemberWrapperList) {
            //CustomTab
            if (sourceMemberWrapper.componentType == 'CustomTab') {
                if (sourceMemberWrapper.id.startsWith('standard'))
                    continue;
            }
            //end of validation
            filteredSourceMemberWrapperList.add(sourceMemberWrapper);
        }

        return filteredSourceMemberWrapperList;
    }

    public static void upsertOrgComponentList(
        List<TrackingService.SourceMemberWrapper> sourceMemberWrapperList,
        String trackingSettingId,
        String organisationId
    ) {
        Map<String, List<Org_Component__c>> orgComponentMap = TrackingService.getAndCreateProcessedSourceMemberRecords(
            sourceMemberWrapperList,
            trackingSettingId,
            organisationId
        );

        for (List<Org_Component__c> orgComponentList : orgComponentMap.values()) {
            for (Org_Component__c orgComponent : orgComponentList) {
                if (!orgComponent.Is_Deleted__c) {
                    orgComponent.Is_Processed__c = true;
                    orgComponent.Status__c = 'In Progress';
                } else {
                    orgComponent.Is_Processed__c = false;
                    orgComponent.Status__c = 'Deleted';
                    orgComponent.Revision_Counter__c = orgComponent.New_Revision_Counter__c;
                    orgComponent.New_Revision_Counter__c = null;
                    orgComponent.Async_Job_Id__c = null;
                }
            }
        }

        DatabaseUtils.updateRecords(
            orgComponentMap.get('updateOrgComponentList'),
            new List<Schema.DescribeFieldResult>{
                Org_Component__c.New_Revision_Counter__c.getDescribe(),
                Org_Component__c.Async_Job_Id__c.getDescribe(),
                Org_Component__c.Is_Deleted__c.getDescribe(),
                Org_Component__c.Is_Processed__c.getDescribe(),
                Org_Component__c.Revision_Counter__c.getDescribe()
            }
        );

        DatabaseUtils.insertRecords(
            orgComponentMap.get('insertOrgComponentList'),
            new List<Schema.DescribeFieldResult>{
                Org_Component__c.OrganisationName__c.getDescribe(),
                Org_Component__c.Tracking_Setting__c.getDescribe(),
                Org_Component__c.Source_Member_Id__c.getDescribe(),
                Org_Component__c.API_Name__c.getDescribe(),
                Org_Component__c.Name__c.getDescribe(),
                Org_Component__c.Component_Type__c.getDescribe(),
                Org_Component__c.New_Revision_Counter__c.getDescribe(),
                Org_Component__c.Is_Deleted__c.getDescribe(),
                Org_Component__c.Is_Processed__c.getDescribe(),
                Org_Component__c.Is_Retrieved__c.getDescribe(),
                Org_Component__c.Status__c.getDescribe(),
                Org_Component__c.Async_Job_Id__c.getDescribe(),
                Org_Component__c.Last_Modified_Date__c.getDescribe(),
                Org_Component__c.Last_Updated_By__c.getDescribe(),
                Org_Component__c.Revision_Counter__c.getDescribe(),
                Org_Component__c.Folder__c.getDescribe()
            }
        );
    }

    public static void handleSuccessSettings(String trackingSettingId) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Name.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingSettingList = [
            SELECT Name
            FROM Tracking_Setting__c
            WHERE Id = :trackingSettingId
        ];
        if (!trackingSettingList.isEmpty()) {
            trackingSettingList.get(0).Is_Processed__c = false;
            trackingSettingList.get(0).Current_Jobs__c = '';
            trackingSettingList.get(0).Current_Apex_Job_Id__c = '';
            DatabaseUtils.updateRecords(
                trackingSettingList,
                new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Current_Jobs__c.getDescribe()
                }
            );
        }
    }

    public static void handleNotProcessedOrgComponents(String trackingSettingId, Logger logger) {
        handleNotProcessedOrgComponents(trackingSettingId, logger, 'Error');
    }

    public static void handleNotProcessedOrgComponents(String trackingSettingId, Logger logger, String status) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Org_Component__c.Name__c.getDescribe(),
                    Org_Component__c.New_Revision_Counter__c.getDescribe(),
                    Org_Component__c.Component_Type__c.getDescribe()
                }
            }
        );

        List<Org_Component__c> orgComponentList = [
            SELECT Name__c, New_Revision_Counter__c, Component_Type__c, Attachment_ID__c
            FROM Org_Component__c
            WHERE Is_Processed__c = :true AND Tracking_Setting__c = :trackingSettingId
            ORDER BY Component_Type__c
            LIMIT 9500
        ];
        if (!orgComponentList.isEmpty()) {
            if (logger != null) {
                logger.addLine('Not process components: ');
            }
            for (Org_Component__c orgComponent : orgComponentList) {
                if (String.isNotBlank(status)) {
                    if (status == 'Error') {
                        orgComponent.Status__c = String.isBlank(orgComponent.Attachment_ID__c) ? status : 'Retrieved';
                    } else {
                        orgComponent.Status__c = status;
                    }
                }

                orgComponent.Revision_Counter__c = null;
                orgComponent.Is_Processed__c = false;
                orgComponent.New_Revision_Counter__c = null;
                orgComponent.Async_Job_Id__c = null;
                if (logger != null) {
                    logger.addLine('Type: ' + orgComponent.Component_Type__c + ', Name: ' + orgComponent.Name__c);
                }
            }
            DatabaseUtils.updateRecords(
                orgComponentList,
                new List<Schema.DescribeFieldResult>{
                    Org_Component__c.Is_Processed__c.getDescribe(),
                    Org_Component__c.Status__c.getDescribe(),
                    Org_Component__c.Revision_Counter__c.getDescribe(),
                    Org_Component__c.New_Revision_Counter__c.getDescribe()
                }
            );
        }
    }

    public static void handleSuccessLog(Logger logger, String message) {
        if (getIsStorageLimitExceeded()) {
            handleErrorLog(logger, STORAGE_LIMIT_EXCEEDED);
            return;
        }
        logger.addLine(message);
        logger.updateLog();
        List<Metadata_Log__c> metadataLogList = [SELECT Name FROM Metadata_Log__c WHERE Id = :logger.parentId];
        if (!metadataLogList.isEmpty()) {
            metadataLogList.get(0).Status__c = 'Completed';
            metadataLogList.get(0).Succeed__c = true;
            metadataLogList.get(0).Job_Completed__c = true;
            metadataLogList.get(0).Completed_Date__c = Datetime.now();
            DatabaseUtils.updateRecords(
                metadataLogList,
                new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Status__c.getDescribe(),
                    Metadata_Log__c.Succeed__c.getDescribe(),
                    Metadata_Log__c.Job_Completed__c.getDescribe(),
                    Metadata_Log__c.Completed_Date__c.getDescribe()
                }
            );
        }
    }

    public static void handleErrorLog(Logger logger, String errorMessage) {
        try {
            List<Metadata_Log__c> metadataLogList = [SELECT Name FROM Metadata_Log__c WHERE Id = :logger.parentId];

            String errorLogMessage = '';
            if (getIsStorageLimitExceeded()) {
                errorLogMessage = STORAGE_LIMIT_EXCEEDED;
            } else {
                logger.addLine(errorMessage);
                logger.updateLog();
            }

            if (!metadataLogList.isEmpty()) {
                metadataLogList.get(0).Status__c = 'Exception';
                metadataLogList.get(0).Is_Error__c = true;
                metadataLogList.get(0).Error_Log__c = errorLogMessage;
                metadataLogList.get(0).Job_Completed__c = true;
                metadataLogList.get(0).Completed_Date__c = Datetime.now();
                DatabaseUtils.updateRecords(
                    metadataLogList,
                    new List<Schema.DescribeFieldResult>{
                        Metadata_Log__c.Status__c.getDescribe(),
                        Metadata_Log__c.Is_Error__c.getDescribe(),
                        Metadata_Log__c.Succeed__c.getDescribe(),
                        Metadata_Log__c.Job_Completed__c.getDescribe(),
                        Metadata_Log__c.Completed_Date__c.getDescribe()
                    }
                );
            }
        } catch (Exception e) {
            System.debug('Tracking.service: handleErrorLog - ' + e.getMessage());
        }
    }

    public static void handleError(String trackingSettingId, Logger logger, String errorMessage) {
        handleErrorLog(logger, errorMessage);
        handleError(trackingSettingId, null);
    }

    public static void handleError(String trackingSettingId, String type, Logger logger, String errorMessage) {
        handleErrorLog(logger, errorMessage);
        handleError(trackingSettingId, type);
    }

    public static void handleError(String trackingSettingId) {
        handleError(trackingSettingId, null);
    }

    public static void handleError(String trackingSettingId, String type) {
        handleErrorSourceMembers(trackingSettingId, type, false);

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Name.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingSettingList = [
            SELECT Name
            FROM Tracking_Setting__c
            WHERE Id = :trackingSettingId
        ];
        if (!trackingSettingList.isEmpty()) {
            trackingSettingList.get(0).Is_Processed__c = false;
            trackingSettingList.get(0).Current_Apex_Job_Id__c = '';
            DatabaseUtils.updateRecords(
                trackingSettingList,
                new List<Schema.DescribeFieldResult>{ Tracking_Setting__c.Is_Processed__c.getDescribe() }
            );
        }
    }

    public static void handleErrorSourceMembers(String trackingSettingId, String type, Boolean isExecute) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Org_Component__c.Name.getDescribe()
                }
            }
        );

        if (!isExecute) {
            Integer componentCount = String.isBlank(type)
                ? [SELECT COUNT() FROM Org_Component__c WHERE Tracking_Setting__c = :trackingSettingId]
                : [
                      SELECT COUNT()
                      FROM Org_Component__c
                      WHERE Tracking_Setting__c = :trackingSettingId AND Component_Type__c = :type
                  ];

            if (componentCount > 8000) {
                try {
                    Database.executeBatch(new TrackingHandleErrorComponentsBatch(trackingSettingId, type));
                    return;
                } catch (Exception e) {
                    System.debug('--- error launch TrackingHandleErrorComponentsBatch ' + e.getMessage());
                }
            }
        }

        List<Org_Component__c> orgComponentList = String.isBlank(type)
            ? [
                  SELECT Id, Attachment_ID__c
                  FROM Org_Component__c
                  WHERE Tracking_Setting__c = :trackingSettingId
                  LIMIT 9500
              ]
            : [
                  SELECT Id, Attachment_ID__c
                  FROM Org_Component__c
                  WHERE Tracking_Setting__c = :trackingSettingId AND Component_Type__c = :type
                  LIMIT 9500
              ];

        handleErrorSourceMembers(orgComponentList);
    }

    public static void handleErrorSourceMembers(List<Org_Component__c> orgComponentList) {
        for (Org_Component__c orgComponent : orgComponentList) {
            orgComponent.Status__c = String.isBlank(orgComponent.Attachment_ID__c) ? 'Error' : 'Retrieved';
            orgComponent.Is_Processed__c = false;
            orgComponent.New_Revision_Counter__c = null;
            orgComponent.Async_Job_Id__c = null;
        }

        DatabaseUtils.upsertRecords(
            orgComponentList,
            new List<Schema.DescribeFieldResult>{
                Org_Component__c.Status__c.getDescribe(),
                Org_Component__c.Is_Processed__c.getDescribe()
            }
        );
    }

    public static String getWhereClause(String lastIdSourceMemberComponent, Tracking_Setting__c trackingSetting) {
        if (String.isBlank(trackingSetting.Metadata_Types__c)) {
            return '';
        }
        String whereClause = '';
        whereClause = '+MemberType+IN+(\'' + trackingSetting.Metadata_Types__c.replaceAll(',', '\',+\'') + '\')';

        if (String.isNotBlank(lastIdSourceMemberComponent)) {
            whereClause += '+AND+Id+>+\'' + lastIdSourceMemberComponent + '\'';
        }
        return whereClause;
    }

    public static String getWhereClause(List<String> componentIdSourceMemberList, Tracking_Setting__c trackingSetting) {
        if (String.isBlank(trackingSetting.Metadata_Types__c)) {
            return '';
        }
        String whereClause = '';
        whereClause = '+MemberType+IN+(\'' + trackingSetting.Metadata_Types__c.replaceAll(',', '\',+\'') + '\')';

        if (componentIdSourceMemberList != null && !componentIdSourceMemberList.isEmpty()) {
            whereClause += '+AND+Id+IN+(\'' + String.join(componentIdSourceMemberList, '\',+\'') + '\')';
        }
        return whereClause;
    }

    public static Map<String, List<Org_Component__c>> getAndCreateProcessedSourceMemberRecords(
        List<TrackingService.SourceMemberWrapper> sourceMemberWrapperList,
        String trackingSettingId,
        String organizationId
    ) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Org_Component__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Org_Component__c.Component_Type__c.getDescribe(),
                    Org_Component__c.Revision_Counter__c.getDescribe(),
                    Org_Component__c.New_Revision_Counter__c.getDescribe(),
                    Org_Component__c.Is_Processed__c.getDescribe(),
                    Org_Component__c.Status__c.getDescribe(),
                    Org_Component__c.Is_Deleted__c.getDescribe(),
                    Org_Component__c.Source_Member_Id__c.getDescribe(),
                    Org_Component__c.Name__c.getDescribe()
                }
            }
        );

        List<Org_Component__c> allOrgComponentList = [
            SELECT
                Name__c,
                Component_Type__c,
                Revision_Counter__c,
                New_Revision_Counter__c,
                Is_Processed__c,
                Status__c,
                Is_Deleted__c,
                Source_Member_Id__c
            FROM Org_Component__c
            WHERE Tracking_Setting__c = :trackingSettingId
        ];

        Map<String, Org_Component__c> nameSourceMemberMap = new Map<String, Org_Component__c>();
        for (Org_Component__c orgComponent : allOrgComponentList) {
            nameSourceMemberMap.put(orgComponent.Name__c + '#' + orgComponent.Component_Type__c, orgComponent);
        }

        List<Org_Component__c> updateOrgComponentList = new List<Org_Component__c>();
        List<Org_Component__c> insertOrgComponentList = new List<Org_Component__c>();
        for (TrackingService.SourceMemberWrapper sourceMemberWrapper : sourceMemberWrapperList) {
            Org_Component__c orgComponent;
            if (
                !nameSourceMemberMap.containsKey(
                    sourceMemberWrapper.componentName +
                    '#' +
                    sourceMemberWrapper.componentType
                )
            ) {
                orgComponent = new Org_Component__c();
                orgComponent.OrganisationName__c = organizationId;
                orgComponent.Tracking_Setting__c = trackingSettingId;
                orgComponent.Source_Member_Id__c = sourceMemberWrapper.memberId;
                orgComponent.API_Name__c = sourceMemberWrapper.componentName;
                orgComponent.Name__c = sourceMemberWrapper.componentName;
                orgComponent.Component_Type__c = sourceMemberWrapper.componentType;
                orgComponent.New_Revision_Counter__c = sourceMemberWrapper.revisionCounter;
                orgComponent.Is_Deleted__c = sourceMemberWrapper.isDeleted;
                orgComponent.Is_Processed__c = false;
                orgComponent.Is_Retrieved__c = false;
                orgComponent.Status__c = 'Pending';
                orgComponent.Async_Job_Id__c = sourceMemberWrapper.asyncJobId;
                orgComponent.Last_Modified_Date__c = Datetime.newInstance(
                    Long.valueOf(sourceMemberWrapper.changedOn.get('value'))
                );
                orgComponent.Last_Updated_By__c = sourceMemberWrapper.changedBy;
                if (FlosumConstants.metadataToFolderMap.containsKey(sourceMemberWrapper.componentType)) {
                    if (sourceMemberWrapper.componentName.contains('/')) {
                        orgComponent.Folder__c = sourceMemberWrapper.componentName.split('/').get(0);
                    }
                }
                insertOrgComponentList.add(orgComponent);
            } else {
                orgComponent = nameSourceMemberMap.get(
                    sourceMemberWrapper.componentName +
                    '#' +
                    sourceMemberWrapper.componentType
                );
                orgComponent.New_Revision_Counter__c = sourceMemberWrapper.revisionCounter;
                orgComponent.Async_Job_Id__c = sourceMemberWrapper.asyncJobId;
                orgComponent.Is_Deleted__c = sourceMemberWrapper.isDeleted;
                orgComponent.Last_Modified_Date__c = Datetime.newInstance(
                    Long.valueOf(sourceMemberWrapper.changedOn.get('value'))
                );
                orgComponent.Last_Updated_By__c = sourceMemberWrapper.changedBy;
                updateOrgComponentList.add(orgComponent);
            }
        }
        return new Map<String, List<Org_Component__c>>{
            'updateOrgComponentList' => updateOrgComponentList,
            'insertOrgComponentList' => insertOrgComponentList
        };
    }

    public static HttpResponse callRequest(String accessToken, String endpoint) {
        HttpRequest httpRequest = new HttpRequest();
        httpRequest.setEndpoint(endpoint);
        httpRequest.setHeader('Authorization', 'Bearer ' + accessToken);
        httpRequest.setMethod('GET');
        httpRequest.setTimeout(120000);
        Http http = new Http();
        return http.send(httpRequest);
    }

    public static void findStackTrackingSetting() {
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
            SELECT Last_Start_Retrieval__c
            FROM Tracking_Setting__c
            WHERE Is_Processed__c = TRUE AND Last_Start_Retrieval__c != NULL
        ];

        List<Tracking_Setting__c> trackingSettingToUpdateList = new List<Tracking_Setting__c>();
        Set<Id> trackingSettingIdSet = new Set<Id>();
        for (Tracking_Setting__c trackingSetting : trackingOrganizationSettingList) {
            Datetime currentDate = Datetime.now();
            Long differenceMilliseconds = currentDate.getTime() - trackingSetting.Last_Start_Retrieval__c.getTime();
            Long differenceSeconds = differenceMilliseconds / 1000;
            Long differenceMinutes = differenceSeconds / 60;
            Long differenceHours = differenceMinutes / 60;
            if (differenceHours > 12) {
                trackingSettingIdSet.add(trackingSetting.Id);
                trackingSetting.Is_Processed__c = false;
                trackingSetting.Current_Jobs__c = '';
                trackingSetting.Current_Apex_Job_Id__c = '';
                trackingSettingToUpdateList.add(trackingSetting);
            }
        }

        DatabaseUtils.updateRecords(
            trackingSettingToUpdateList,
            new List<Schema.DescribeFieldResult>{
                Tracking_Setting__c.Is_Processed__c.getDescribe(),
                Tracking_Setting__c.Current_Apex_Job_Id__c.getDescribe(),
                Tracking_Setting__c.Current_Jobs__c.getDescribe()
            }
        );

        List<Metadata_Log__c> metadataLogList = [
            SELECT Id, Status__c, CreatedDate, Start_Date__c
            FROM Metadata_Log__c
            WHERE Tracking_Setting__c IN :trackingSettingIdSet AND Status__c = 'In Progress'
        ];

        List<Metadata_Log__c> metadataLogToUpdateList = new List<Metadata_Log__c>();
        for (Metadata_Log__c metadataLog : metadataLogList) {
            Datetime currentDate = Datetime.now();
            Long differenceMilliseconds = currentDate.getTime() - metadataLog.Start_Date__c.getTime();
            Long differenceSeconds = differenceMilliseconds / 1000;
            Long differenceMinutes = differenceSeconds / 60;
            Long differenceHours = differenceMinutes / 60;
            if (differenceHours > 12) {
                metadataLog.Status__c = 'Exception';
                metadataLog.Is_Error__c = true;
                metadataLog.Error_Log__c = 'Retrieve a stack.';
                metadataLog.Job_Completed__c = true;
                metadataLog.Completed_Date__c = Datetime.now();
                metadataLogToUpdateList.add(metadataLog);
            }
        }

        DatabaseUtils.updateRecords(
            metadataLogToUpdateList,
            new List<Schema.DescribeFieldResult>{
                Metadata_Log__c.Status__c.getDescribe(),
                Metadata_Log__c.Is_Error__c.getDescribe(),
                Metadata_Log__c.Succeed__c.getDescribe(),
                Metadata_Log__c.Job_Completed__c.getDescribe(),
                Metadata_Log__c.Completed_Date__c.getDescribe()
            }
        );
    }

    private static List<TrackingService.SourceMemberWrapper> convertSourceMembers(
        List<TrackingService.ApexRestResponseRecordWrapper> apexRestResponseRecordWrapperList
    ) {
        List<TrackingService.SourceMemberWrapper> sourceMemberWrapperList = new List<TrackingService.SourceMemberWrapper>();

        for (
            TrackingService.ApexRestResponseRecordWrapper apexRestResponseRecordWrapper : apexRestResponseRecordWrapperList
        ) {
            sourceMemberWrapperList.add(new TrackingService.SourceMemberWrapper(apexRestResponseRecordWrapper));
        }

        return sourceMemberWrapperList;
    }

    private static List<TrackingService.RetrieveComponentWrapper> convertToRetrieveComponentWrapper(
        List<Org_Component__c> orgComponentList
    ) {
        List<TrackingService.RetrieveComponentWrapper> retrieveComponentWrapperList = new List<TrackingService.RetrieveComponentWrapper>();
        Map<String, List<Org_Component__c>> typeOrgComponentListMap = new Map<String, List<Org_Component__c>>();
        for (Org_Component__c orgComponent : orgComponentList) {
            if (typeOrgComponentListMap.containsKey(orgComponent.Component_Type__c)) {
                typeOrgComponentListMap.get(orgComponent.Component_Type__c).add(orgComponent);
            } else {
                typeOrgComponentListMap.put(orgComponent.Component_Type__c, new List<Org_Component__c>{ orgComponent });
            }
        }

        for (String componentType : typeOrgComponentListMap.keySet()) {
            RetrieveComponentWrapper retrieveComponentWrapper = new RetrieveComponentWrapper();
            retrieveComponentWrapper.type = componentType;
            retrieveComponentWrapper.componentList = new List<TrackingService.SourceMemberWrapper>();
            for (Org_Component__c orgComponent : typeOrgComponentListMap.get(componentType)) {
                retrieveComponentWrapper.componentList.add(new SourceMemberWrapper(orgComponent));
            }
            retrieveComponentWrapperList.add(retrieveComponentWrapper);
        }

        return retrieveComponentWrapperList;
    }

    public static void checkIsTrackingIsProcess(
        String trackingSettingId,
        Database.BatchableContext context,
        Logger logger
    ) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Is_Processed__c.getDescribe(),
                    Tracking_Setting__c.Last_Start_Retrieval__c.getDescribe(),
                    Tracking_Setting__c.Organization__c.getDescribe(),
                    Tracking_Setting__c.Metadata_Types__c.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingSettingList = [
            SELECT Is_Processed__c, Last_Start_Retrieval__c, Organization__c, Is_Enabled__c, Metadata_Types__c
            FROM Tracking_Setting__c
            WHERE Id = :trackingSettingId
        ];

        if (!trackingSettingList.isEmpty()) {
            if (!trackingSettingList.get(0).Is_Processed__c) {
                System.abortJob(context.getJobId());
                TrackingService.handleNotProcessedOrgComponents(trackingSettingId, logger, 'Pending');
            }
        }
    }

    public static void setApexJobIdSetting(String trackingSettingId, String apexJobId) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Id.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Id
            FROM Tracking_Setting__c
            WHERE Id = :trackingSettingId
        ];
        if (!trackingOrganizationSettingList.isEmpty()) {
            trackingOrganizationSettingList.get(0).Current_Apex_Job_Id__c = apexJobId;
            DatabaseUtils.upsertRecord(
                trackingOrganizationSettingList.get(0),
                new List<Schema.DescribeFieldResult>{ Tracking_Setting__c.Current_Apex_Job_Id__c.getDescribe() }
            );
        }
    }

    public static Logger createLogger(String trackingSettingId) {
        TrackingService.Logger logger = null;

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Organization__c.getDescribe()
                }
            }
        );

        List<Tracking_Setting__c> trackingOrganizationSettingList = [
            SELECT Id, Organization__c
            FROM Tracking_Setting__c
            WHERE Id = :trackingSettingId
        ];

        if (trackingOrganizationSettingList.isEmpty()) {
            throw new FlosumException('TrackingSetting not found.');
        }

        Metadata_Log__c metadataLog = TrackingService.createLog(
            trackingOrganizationSettingList.get(0).Organization__c,
            trackingOrganizationSettingList.get(0).Id,
            TrackingService.PROCESS_TYPE_RETRIEVE_ORGANIZATION,
            TrackingService.TRACKING_ORGANIZATION_LOG_NAME
        );

        logger = new TrackingService.Logger(metadataLog.Id, TrackingService.TRACKING_ORGANIZATION_LOG_NAME);

        return logger;
    }

    public static void abortScheduler(String organizationId) {
        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                CronTrigger.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    CronTrigger.CronJobDetailId.getDescribe()
                }
            }
        );
        List<CronTrigger> cronList = [
            SELECT Id, CronJobDetailId, CronJobDetail.Name
            FROM CronTrigger
            WHERE
                CronJobDetail.Name IN :new List<String>{
                    'Tracking Automation ' + organizationId,
                    'Tracking Check Retrieve ' + organizationId
                }
        ];
        for (CronTrigger cronTrigger : cronList) {
            System.abortJob(cronTrigger.Id);
        }
    }

    public static Boolean getIsStorageLimitExceeded() {
        Set<String> limitOrgExceededSet = checkExceededOrgLimits();
        if (limitOrgExceededSet.isEmpty())
            return false;
        Boolean isLimitStorageExceeded =
            limitOrgExceededSet.contains('DataStorageMB') || limitOrgExceededSet.contains('FileStorageMB');
        return !Test.isRunningTest() ? isLimitStorageExceeded : false;
    }

    public static Set<String> checkExceededOrgLimits() {
        Map<String, System.OrgLimit> limitsMap = OrgLimits.getMap();
        Map<String, System.OrgLimit> resultLimitMap = new Map<String, OrgLimit>();
        Set<String> resultLimitSet = new Set<String>();
        for (String nameLimit : limitsMap.keySet()) {
            System.OrgLimit apiRequestsLimit = limitsMap.get(nameLimit);
            if (apiRequestsLimit.getValue() > apiRequestsLimit.getLimit()) {
                resultLimitMap.put(nameLimit, apiRequestsLimit);
                resultLimitSet.add(nameLimit);
            }
        }
        return resultLimitSet;
    }

    public static void removeTrackingSettingsAsync(List<Organisation__c> organizationList) {
        System.enqueueJob(new RemoveTrackingSettingQueueable(organizationList));
    }

    public static void removeTrackingSettings(List<Organisation__c> organizationList) {
        Set<String> sourceOrganizationIdSet = new Set<String>();
        for (Organisation__c organisation : organizationList) {
            sourceOrganizationIdSet.add(organisation.Organisation_ID__c);
        }

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Tracking_Setting__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Tracking_Setting__c.Id.getDescribe()
                }
            }
        );

        Map<Id, Tracking_Setting__c> trackingSettingMap = new Map<Id, Tracking_Setting__c>(
            [
                SELECT Id, Organization__c
                FROM Tracking_Setting__c
                WHERE Source_Organization_Id__c IN :sourceOrganizationIdSet
            ]
        );

        DatabaseUtils.checkObjectsAndFieldsAccessibility(
            new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                Metadata_Log__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                    Metadata_Log__c.Id.getDescribe()
                }
            }
        );

        List<Metadata_Log__c> metadataLogList = [
            SELECT Id
            FROM Metadata_Log__c
            WHERE Tracking_Setting__c IN :trackingSettingMap.keySet()
            LIMIT 40000
        ];

        DatabaseUtils.deleteRecords(metadataLogList);
        DatabaseUtils.deleteRecords(trackingSettingMap.values());
    }

    public class RemoveTrackingSettingQueueable implements Queueable {
        List<Organisation__c> organizationList;
        private Integer count;

        public RemoveTrackingSettingQueueable(List<Organisation__c> organizationList) {
            this.organizationList = organizationList;
            count = 1;
        }

        public RemoveTrackingSettingQueueable(List<Organisation__c> organizationList, Integer count) {
            this.organizationList = organizationList;
            this.count = count;
        }

        public void execute(QueueableContext queueableContext) {
            TrackingService.removeTrackingSettings(organizationList);
            Integer metadataLogCount = [
                SELECT COUNT()
                FROM Metadata_Log__c
                WHERE
                    Tracking_Setting__c IN (
                        SELECT Id
                        FROM Tracking_Setting__c
                        WHERE Organization__c IN :organizationList
                    )
            ];
            if (metadataLogCount > 0 && count < 6 && !Test.isRunningTest()) {
                System.enqueueJob(new RemoveTrackingSettingQueueable(organizationList, count));
            }
        }
    }

    public class Logger {
        public String parentId;
        public String logName;
        public List<String> logFile;

        public Logger(String parentId, String logName) {
            this.parentId = parentId;
            this.logName = logName;
            logFile = new List<String>();
        }

        public void addLine(String line) {
            if (String.isBlank(line)) {
                return;
            }

            logFile.add(Datetime.now().format('MM-dd-yyyy HH:mm:ss') + ' ' + line + '\n');
        }

        public void addTemplateLine(String template, List<String> arguments) {
            if (String.isBlank(template) || arguments.isEmpty()) {
                return;
            }

            String line = String.format(template, arguments);

            logFile.add(Datetime.now().format('MM-dd-yyyy HH:mm:ss') + ' ' + line + '\n');
        }

        public Attachment updateLog(Boolean isUpdateLog) {
            if (!logFile.isEmpty() && String.isNotBlank(parentId) && String.isNotBlank(logName)) {
                if (getIsStorageLimitExceeded()) {
                    handleErrorLog(this, STORAGE_LIMIT_EXCEEDED);
                    return null;
                }

                DatabaseUtils.checkObjectsAndFieldsAccessibility(
                    new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                        Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                            Attachment.Body.getDescribe(),
                            Attachment.BodyLength.getDescribe(),
                            Attachment.ParentId.getDescribe(),
                            Attachment.CreatedDate.getDescribe()
                        }
                    }
                );
                List<Attachment> attachmentLogList = [
                    SELECT Id, Body, BodyLength
                    FROM Attachment
                    WHERE ParentId = :parentId AND Name = :logName
                    ORDER BY CreatedDate DESC
                    LIMIT 1
                ];
                Attachment attachmentLog;
                String newLog = String.join(logFile, ' ');
                if (newLog.length() > 400000) {
                    List<String> logList1 = new List<String>();
                    List<String> logList2 = new List<String>();

                    Integer splitter = logFile.size() / 2;
                    for (Integer i = 0; i < logFile.size(); i++) {
                        if (i < splitter) {
                            logList1.add(logFile.get(i));
                        } else {
                            logList2.add(logFile.get(i));
                        }
                    }
                    String newLog1 = String.join(logList1, ' ');
                    String newLog2 = String.join(logList2, ' ');
                    attachmentLog = updateAttachment(newLog1, isUpdateLog);
                    attachmentLog = updateAttachment(newLog2, isUpdateLog);
                } else {
                    attachmentLog = updateAttachment(newLog, isUpdateLog);
                }

                logFile.clear();

                return attachmentLog;
            }
            return null;
        }

        private Attachment updateAttachment(String newLog, Boolean isUpdateLog) {
            DatabaseUtils.checkObjectsAndFieldsAccessibility(
                new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
                    Attachment.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{
                        Attachment.Body.getDescribe(),
                        Attachment.BodyLength.getDescribe(),
                        Attachment.ParentId.getDescribe(),
                        Attachment.CreatedDate.getDescribe()
                    }
                }
            );
            List<Attachment> attachmentLogList = [
                SELECT Id, Body, BodyLength
                FROM Attachment
                WHERE ParentId = :parentId AND Name = :logName
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            String log = '';
            Attachment attachmentLog;
            if (!attachmentLogList.isEmpty()) {
                if (attachmentLogList[0].BodyLength > 1500000) {
                    attachmentLog = new Attachment(
                        Name = logName,
                        ParentId = parentId,
                        Body = Blob.valueOf(newLog),
                        ContentType = 'text/plain'
                    );
                } else {
                    log = attachmentLogList[0].Body.toString() + newLog;
                    attachmentLog = attachmentLogList[0];
                    attachmentLog.Body = Blob.valueOf(log);
                }
            } else {
                attachmentLog = new Attachment(
                    Name = logName,
                    ParentId = parentId,
                    Body = Blob.valueOf(newLog),
                    ContentType = 'text/plain'
                );
            }

            if (isUpdateLog) {
                DatabaseUtils.upsertRecord(
                    attachmentLog,
                    new List<Schema.DescribeFieldResult>{
                        Attachment.Name.getDescribe(),
                        Attachment.Body.getDescribe(),
                        Attachment.ContentType.getDescribe()
                    }
                );
            }
            return attachmentLog;
        }

        public void updateLog() {
            updateLog(true);
        }
    }

    public class TrackingOrganizationWrapper {
        public String currentJobs;
        public List<String> metadataTypeList;
        public Boolean isEnabled;
        public Boolean isProcessed;

        public TrackingOrganizationWrapper(Tracking_Setting__c trackingOrganizationSetting) {
            this.currentJobs = trackingOrganizationSetting.Current_Jobs__c;
            this.metadataTypeList = trackingOrganizationSetting.Metadata_Types__c != null
                ? trackingOrganizationSetting.Metadata_Types__c.split(',')
                : new List<String>();
            this.isEnabled = trackingOrganizationSetting.Is_Enabled__c;
            this.isProcessed = trackingOrganizationSetting.Is_Processed__c;
        }
    }

    public class RetrieveComponentWrapper {
        public String type;
        public Boolean isDependency;
        public List<SourceMemberWrapper> componentList;
        public List<RetrieveComponentWrapper> dependencyList;

        public RetrieveComponentWrapper() {
            isDependency = false;
            dependencyList = new List<TrackingService.RetrieveComponentWrapper>();
        }

        public RetrieveComponentWrapper(String type, Set<String> componentNameSet) {
            this(type, new List<String>(componentNameSet));
        }

        public RetrieveComponentWrapper(String type, List<String> componentNameList) {
            this.type = type;
            dependencyList = new List<RetrieveComponentWrapper>();
            componentList = new List<SourceMemberWrapper>();
            isDependency = true;
            for (String componentName : componentNameList) {
                componentList.add(new SourceMemberWrapper(componentName));
            }
        }

        public RetrieveComponentWrapper(String type) {
            this(type, new List<SourceMemberWrapper>());
        }

        public RetrieveComponentWrapper(String type, List<SourceMemberWrapper> componentList) {
            this.type = type;
            this.componentList = componentList;
            dependencyList = null;
            isDependency = null;
        }
    }

    public class SourceMemberPacksWrapper {
        public List<SourceMemberWrapper> changedList;
        public List<SourceMemberWrapper> tooLargeList;
        public String nextRecordUrl;
        public String lastId;

        public SourceMemberPacksWrapper(List<SourceMemberWrapper> changedList, List<SourceMemberWrapper> tooLargeList) {
            this.changedList = changedList;
            this.tooLargeList = tooLargeList;
        }

        public SourceMemberPacksWrapper(
            List<SourceMemberWrapper> changedList,
            List<SourceMemberWrapper> tooLargeList,
            String nextRecordUrl
        ) {
            this.changedList = changedList;
            this.tooLargeList = tooLargeList;
            this.nextRecordUrl = nextRecordUrl;
        }
        public SourceMemberPacksWrapper(
            List<SourceMemberWrapper> changedList,
            List<SourceMemberWrapper> tooLargeList,
            String nextRecordUrl,
            String lastId
        ) {
            this.changedList = changedList;
            this.tooLargeList = tooLargeList;
            this.nextRecordUrl = nextRecordUrl;
            this.lastId = lastId;
        }

        public SourceMemberPacksWrapper() {
            this.changedList = new List<SourceMemberWrapper>();
            this.tooLargeList = new List<SourceMemberWrapper>();
        }

        public void sortChangedListByType() {
            Map<String, List<SourceMemberWrapper>> mapChangedList = getChangedMap();

            List<String> typeList = new List<String>(mapChangedList.keySet());
            typeList.sort();

            List<SourceMemberWrapper> newChangedList = new List<SourceMemberWrapper>();

            for (String type : typeList) {
                newChangedList.addAll(mapChangedList.get(type));
            }
            this.changedList = newChangedList;
        }

        public Map<String, List<SourceMemberWrapper>> getChangedMap() {
            if (this.changedList == null || this.changedList.isEmpty()) {
                return new Map<String, List<SourceMemberWrapper>>();
            }

            Map<String, List<SourceMemberWrapper>> mapChangedList = new Map<String, List<SourceMemberWrapper>>();

            for (SourceMemberWrapper smw : this.changedList) {
                if (String.isBlank(smw.componentType))
                    continue;

                if (mapChangedList.containsKey(smw.componentType)) {
                    mapChangedList.get(smw.componentType).add(smw);
                } else {
                    List<SourceMemberWrapper> typeChangedList = new List<SourceMemberWrapper>{ smw };
                    mapChangedList.put(smw.componentType, typeChangedList);
                }
            }
            return mapChangedList;
        }

        public Map<String, List<SourceMemberWrapper>> getTooLargeMap() {
            return getTypeListMap(this.tooLargeList);
        }

        private Map<String, List<SourceMemberWrapper>> getTypeListMap(
            List<SourceMemberWrapper> sourceMemberWrapperList
        ) {
            if (sourceMemberWrapperList == null || sourceMemberWrapperList.isEmpty()) {
                return new Map<String, List<SourceMemberWrapper>>();
            }

            Map<String, List<SourceMemberWrapper>> sourceMemberWrapperMap = new Map<String, List<SourceMemberWrapper>>();

            for (SourceMemberWrapper smw : sourceMemberWrapperList) {
                if (String.isBlank(smw.componentType))
                    continue;

                if (sourceMemberWrapperMap.containsKey(smw.componentType)) {
                    sourceMemberWrapperMap.get(smw.componentType).add(smw);
                } else {
                    List<SourceMemberWrapper> typeChangedList = new List<SourceMemberWrapper>{ smw };
                    sourceMemberWrapperMap.put(smw.componentType, typeChangedList);
                }
            }
            return sourceMemberWrapperMap;
        }
    }

    public class SourceMemberWrapper {
        public Map<String, String> changedOn;
        public String changedBy;
        public String changedById;
        public String componentName;
        public String componentType;
        public String id;
        public String memberId;
        public String sourceMemberId;
        public String asyncJobId;
        public String changedComponentNumber;
        public String status;
        public String statusLabel;
        public Integer revisionCounter;
        public Boolean isDeleted;
        public Boolean isNew;
        public Boolean isRetrieveManually;

        public SourceMemberWrapper() {
        }

        public SourceMemberWrapper(String componentName) {
            this.componentName = componentName;
            isDeleted = false;
        }

        public SourceMemberWrapper(ApexRestResponseRecordWrapper apexRestResponseRecordWrapper) {
            Datetime dt = apexRestResponseRecordWrapper.LastModifiedDate == null
                ? Datetime.newInstance(0)
                : apexRestResponseRecordWrapper.LastModifiedDate;
            changedOn = new Map<String, String>{
                'label' => dt.format('M/d/yyyy, h:mm aaa'),
                'value' => dt.getTime() + ''
            };
            changedById = apexRestResponseRecordWrapper.ChangedBy;
            changedBy = apexRestResponseRecordWrapper.LastModifiedBy == null
                ? ''
                : apexRestResponseRecordWrapper.LastModifiedBy.Name;
            componentName = apexRestResponseRecordWrapper.MemberName;
            componentType = apexRestResponseRecordWrapper.MemberType;
            id = apexRestResponseRecordWrapper.MemberIdOrName; //putanitsa
            memberId = apexRestResponseRecordWrapper.Id; //putanitsa
            revisionCounter = apexRestResponseRecordWrapper.RevisionCounter;
            isDeleted = componentType == 'Profile' ||
                componentType == 'RecordType'
                ? false
                : apexRestResponseRecordWrapper.IsNameObsolete == null
                      ? false
                      : apexRestResponseRecordWrapper.IsNameObsolete;
            isNew = apexRestResponseRecordWrapper.IsNewMember;
            status = 'Not Retrieved';
            statusLabel = isDeleted ? 'Deleted' : 'Change detected';
        }

        public SourceMemberWrapper(Org_Component__c orgComponent) {
            Datetime dt = orgComponent.Last_Modified_Date__c == null
                ? Datetime.newInstance(0)
                : orgComponent.Last_Modified_Date__c;
            changedOn = new Map<String, String>{
                'label' => dt.format('M/d/yyyy, h:mm aaa'),
                'value' => dt.getTime() + ''
            };
            changedById = orgComponent.Last_Updated_By__c;
            changedBy = orgComponent.Last_Updated_By__c;
            componentName = orgComponent.Name__c;
            componentType = orgComponent.Component_Type__c;
            isDeleted = orgComponent.Is_Deleted__c;
            revisionCounter = Integer.valueOf(orgComponent.Revision_Counter__c);
            status = orgComponent.Status__c;
            statusLabel = orgComponent.Status__c;
            isRetrieveManually = status == 'Too Large' && componentType == 'Profile';

            if (isRetrieveManually){
                statusLabel = 'Retrieve Manually';
            }                

            if (status == 'Retrieved'){
                statusLabel = 'Component Retrieved';
            }                

            id = orgComponent.Id;
            memberId = orgComponent.Source_Member_Id__c;
            changedComponentNumber = orgComponent.Name;
        }
    }

    public class ApexRestResponseWrapper {
        public String entityTypeName;
        public Integer size;
        public Integer totalSize;
        public String nextRecordsUrl;
        public Boolean done;
        public List<ApexRestResponseRecordWrapper> records;

        public ApexRestResponseWrapper() {
            this.records = new List<ApexRestResponseRecordWrapper>();
        }
    }

    public class ApexRestResponseRecordWrapper {
        public String ChangedBy;
        public Datetime LastModifiedDate;
        public ApexRestResponseLastModifiedBy LastModifiedBy;
        public String MemberName {
            get {
                return MemberName;
            }
            set {
                if (String.isBlank(MemberType)) {
                    MemberName = value;
                } else {
                    MemberName = fixMemberName(value, MemberType);
                }
            }
        }
        public String MemberType {
            get {
                return MemberType;
            }
            set {
                MemberType = value;
                if (MemberName != null) {
                    MemberName = MemberName;
                }
            }
        }
        public String MemberIdOrName;
        public String Id;
        public Integer BodyLength;
        public Integer SourceMemberSize;
        public String sourceMemberId;
        public Integer RevisionCounter;
        public Boolean IsNameObsolete;
        public Boolean IsNewMember;

        public String fixMemberName(String memberName, String memberType) {
            if (memberName.startsWith('Knowledge__c')) {
                memberName = memberName.replaceFirst('__c', '__kav');
            } else {
                memberName = FlosumUtils.decode(memberType, memberName);
            }
            return memberName;
        }
    }
    public class ApexRestResponseLastModifiedBy {
        public String Name;
    }

    public class LogWrapper {
        public String id;
        public String status;
        public Boolean isCompleted;
        public String body;
        public String completedDate;
        public String startedDate;
        public String errorMessage;

        public LogWrapper(
            String id,
            String status,
            Boolean isCompleted,
            Datetime startedDate,
            Datetime completedDate,
            String errorMessage
        ) {
            this.id = id;
            this.status = status;
            this.errorMessage = errorMessage;
            this.isCompleted = isCompleted;
            if (startedDate != null) {
                this.startedDate = startedDate.format('MM-dd-yyyy HH:mm:ss');
            }
            if (completedDate != null) {
                this.completedDate = completedDate.format('MM-dd-yyyy HH:mm:ss');
            }
            body = '';
        }

        public LogWrapper(
            String id,
            String status,
            String body,
            Boolean isCompleted,
            Datetime startedDate,
            Datetime completedDate,
            String errorMessage
        ) {
            this.id = id;
            this.status = status;
            this.body = body;
            this.errorMessage = errorMessage;
            this.isCompleted = isCompleted;
            if (startedDate != null) {
                this.startedDate = startedDate.format('MM-dd-yyyy HH:mm:ss');
            }
            if (completedDate != null) {
                this.completedDate = completedDate.format('MM-dd-yyyy HH:mm:ss');
            }
        }
    }

    public class AsyncJobIdAndOrgComponentListsWrapper {
        public List<String> asyncJobList;
        public List<Org_Component__c> orgComponentList;
    }

    public class StartJobRequestWrapper {
        public CredentialsWrapper flosumOrgCredentials;
        public CredentialsWrapper targetOrgCredentials;
        public Datetime lastRetrieveDate;
        public String targetOrgId;
        public String trackingSettingId;
        public String apiVersion;
        public List<String> metadataTypes;
        public String timeZone;

        public StartJobRequestWrapper(
            Datetime lastRetrieveDate,
            String targetOrgId,
            String trackingSettingId,
            String metadataTypes,
            String timeZone
        ) {
            this.flosumOrgCredentials = new CredentialsWrapper();
            this.targetOrgCredentials = new CredentialsWrapper();
            this.lastRetrieveDate = lastRetrieveDate;
            this.targetOrgId = targetOrgId;
            this.trackingSettingId = trackingSettingId;
            this.apiVersion = FlosumConstants.apiversion + '.0';
            this.metadataTypes = metadataTypes.split(',');
            this.timeZone = timeZone;
        }
    }

    public class CredentialsWrapper {
        public String accessToken;
        public String instanceUrl;
        public String refreshToken;
        public String clientId;
        public String clientSecret;
    }

    public class AgentJobWrapper {
        public String jobId;
    }
}