public with sharing class ScheduleSnapshotRetrievalBatch implements Database.batchable<sobject>,Database.AllowsCallouts,Database.Stateful
{
	public String orgId;
	public Set<String> metadataTypes;
	public Integer noOfDays;
	public String filterJSON;
	
	private String query;
		
	public ScheduleSnapshotRetrievalBatch(Set<String> metaTypeSet, String orgId, Integer noOfDays, String filterJSON)
    {
		System.debug('ScheduleSnapshotRetrievalBatch');
		System.debug('metaTypeSet >>> ' + metaTypeSet);
		System.debug('orgId >>> ' + orgId);
		System.debug('noOfDays >>> ' + noOfDays);
		System.debug('filterJSON >>> ' + filterJSON);
    	this.orgId = orgId;
		this.metadataTypes = metaTypeSet;
		this.noOfDays = noOfDays;
		this.filterJSON = filterJSON;
		this.query =  'SELECT Id FROM Organisation__c WHERE Id =: orgId';
    }
	
	public Database.QueryLocator start(Database.BatchableContext BC)
    {
		DatabaseUtils.checkObjectsAndFieldsAccessibility(new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
			Organisation__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
		});
    	return Database.getQueryLocator(query);
    }
    
    public void execute(Database.BatchableContext BC, List<sObject> scope)
    {
        
    }
    
    public void finish(Database.BatchableContext BC)
    {
        try
    	{
			Boolean isExternal = ExternalSnapshotService.isExternalRetrievalEnabled();
	    	//AuthUtils.AuthenticateDetails authDetails = AuthUtils.authenticateAnOrg(this.orgId,FlosumConstants.DEVELOPER);
			FlosumUtils controller = new FlosumUtils();
            FlosumUtils.AuthenticateDetails authDetails = controller.authenticateAnOrg(orgId);
	        if(authDetails.isSuccess && authDetails.details != null && this.metadataTypes != null)
	        {
	        	// List available Metadata Types via the 'describeMetadata' API call
	            MetadataService.MetadataPort service = MetadataUtils.createService(authDetails.details.AccessToken__c,authDetails.details.InstanceURL__c);                    
	            MetadataService.DescribeMetadataResult describeResult = service.describeMetadata(FlosumConstants.apiversion);
	            List<String> metadataTypeNames = new List<String>(); 
	                     
	            for(MetadataService.DescribeMetadataObject metadataObject : describeResult.metadataObjects)
	            {
	            	if(this.metadataTypes.contains(metadataObject.xmlName) && metadataObject.xmlName != 'CustomLabels')
	                	metadataTypeNames.add(metadataObject.xmlName);
	                	
	                // Include child Metadata Types (such as CustomField, ValidationRule etc..)
	                if(metadataObject.childXmlNames!=null)
	                {
	                    for(String childXmlName : metadataObject.childXmlNames)
	                    {
	                        if(childXmlName!=null && this.metadataTypes.contains(childXmlName))
	                        {
	                            metadataTypeNames.add(childXmlName);
	                        }
	                    }
	                }
	            }   
	        	if(metadataTypeNames.size() > 0)
	        	{
					DatabaseUtils.checkObjectsAndFieldsAccessibility(new Map<Schema.DescribeSObjectResult, List<Schema.DescribeFieldResult>>{
						Organisation__c.getSObjectType().getDescribe() => new List<Schema.DescribeFieldResult>{}
					});
		        	List<Organisation__c> orgLi = [SELECT Id,Name from Organisation__c Where Id=:this.orgId LIMIT 1];
		        	if(orgLi != null && orgLi.size() > 0)
		        	{
		        		String year = string.valueOf(system.now().year());
						String month = string.valueOf(system.now().month());
						String day = string.valueOf(system.now().day());
						String hour = string.valueOf(system.now().hour());
						String minute = string.valueOf(system.now().minute());
						String second = string.valueOf(system.now().second());
						
						if(Integer.valueOf(month) < 10)
    						month = '0'+month;
    					if(Integer.valueOf(day) < 10)
    						day = '0'+day;
    					if(Integer.valueOf(minute) < 10)
    						minute = '0'+minute;
    					if(Integer.valueOf(second) < 10)
    						second = '0'+second;
    					    						
						String currentTime = year+'/'+month+'/'+day+' '+hour+':'+minute+':'+second;
		        		
						String snapName = orgLi[0].Name +' - '+ currentTime;
						if(snapName.length() > 80){
							snapName = orgLi[0].Name.substring(0,50) +' - '+ currentTime;
						}
						DateTime tempDt = System.now();
			        	if(noOfDays != null && noOfDays != 0)
			            {
			                tempDt = tempDt.addDays(-noOfDays);
			            }
			            else
			            	tempDt = null;
						
						FlosumUtils.SnapshotFilterInfo tempFilterInfo = (FlosumUtils.SnapshotFilterInfo) JSON.deserialize(filterJSON, FlosumUtils.SnapshotFilterInfo.class);

						FlosumUtils.ReCreateSnapshotFilterWraper reCreateSnapshot = new FlosumUtils.ReCreateSnapshotFilterWraper(metadataTypeNames,tempDt,tempFilterInfo);
                    	String reCreateSnapshotString =  JSON.serialize(reCreateSnapshot);
						Snapshot__c snap = new Snapshot__c();
						ExternalSnapshotService.RetrieveRequest bodyObj = new ExternalSnapshotService.RetrieveRequest();
						if(isExternal) {
                            bodyObj.credentials.accessToken = authDetails.details.AccessToken__c;
                            bodyObj.credentials.instanceUrl = authDetails.details.InstanceURL__c;
                            bodyObj.credentials.refreshToken = authDetails.details.RefreshToken__c;
                            bodyObj.credentials.clientId = authDetails.clientId;
                            bodyObj.credentials.clientSecret = authDetails.clientSecret;
                            bodyObj.metadataTypes = metadataTypeNames;
                            bodyObj.declarativeFilter = CreateMultiMetaSnapshotController.parsefiltersToExternalFormat(reCreateSnapshot);
                            String endpoint = ExternalSnapshotService.ExternalJobURL;
                            String reqBody = JSON.serialize(bodyObj);
							System.debug('endpoint >>> ' + endpoint);
							System.debug('reqBody >>> ' + reqBody);
                            String response = ExternalSnapshotService.makeApiCall(endpoint, JSON.serialize(bodyObj),'POST');
                            ExternalSnapshotService.JobStatus status = (ExternalSnapshotService.JobStatus) JSON.deserialize(response, ExternalSnapshotService.JobStatus.class);
							System.debug('status: ' + status);
							if(status != null && status.jobId != null) {
                                snap.External_Job_Id__c = status.jobId;
                                snap.Is_External_Snapshot__c = true;
                                snap.External_Status__c = ExternalSnapshotBatch.Request_InQueue;
							}
						}
						snap.Organisation__c = orgId;
                        snap.Name = snapName;
						snap.Last_Modified_In_Days__c = noOfDays;
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
						if(isExternal) {
							bodyObj.credentials = null;
							Attachment att = new Attachment();
							att.Name = 'FilterBody.json';
							att.Body = Blob.valueOf(JSON.serialize(bodyObj));
							att.ParentId = snap.Id;
							att.ContentType = 'application/json';
							insert att;
						}

				        Metadata_Log__c ApexLogRecord = new Metadata_Log__c(); 
			            ApexLogRecord.Organisation__c = this.orgId;
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
			            JSLogRecord.Organisation__c = this.orgId;
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
						if(isExternal){
							ExternalSnapshotBatch.init();
                            return;
						}
						else {
							Database.executeBatch(new ComponentQueryBatch(metadataTypeNames,authDetails.details.AccessToken__c,authDetails.details.InstanceURL__c,snap.Id,tempDt,filterJSON),1);
						}
		        	}
	        	}
	        }
    	}
    	catch(Exception ex)
    	{
    		System.debug('Exception--'+ex.getMessage());
    	}
    }
}