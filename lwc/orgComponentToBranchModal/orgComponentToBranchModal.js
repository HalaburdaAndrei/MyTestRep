import { track, api, LightningElement } from 'lwc';
import { utils } from 'c/utils';
import { loadScript } from 'lightning/platformResourceLoader';

import searchBranchLookup from '@salesforce/apex/TrackingOrganizationController.searchBranchLookup';
import getCommitToBranchOptions from '@salesforce/apex/TrackingOrganizationController.getCommitToBranchOptions';
import checkCommitPermissions from '@salesforce/apex/TrackingOrganizationController.checkCommitPermissions';
import getBranchPipelineInfo from '@salesforce/apex/TrackingOrganizationController.getBranchPipelineInfo';
import insertMergeSetAttachment from '@salesforce/apex/TrackingOrganizationController.insertMergeSetAttachment';
import getOrgComponentsInfo from '@salesforce/apex/TrackingOrganizationController.getOrgComponentsInfo';
import getHistoryComparisonUrl from '@salesforce/apex/TrackingOrganizationController.getHistoryComparisonUrl';
import getAttachmentsInfo from '@salesforce/apex/TrackingOrganizationController.getAttachmentsInfo';
import getAttachmentsBody from '@salesforce/apex/TrackingOrganizationController.getAttachmentsBody';
import compareOrgComponentsAndBranchComponents from '@salesforce/apex/TrackingOrganizationController.compareOrgComponentsAndBranchComponents';
import prepareToCommit from '@salesforce/apex/TrackingOrganizationController.prepareToCommit';
import commitToBranch from '@salesforce/apex/TrackingOrganizationController.commitToBranch';
import completeCommit from '@salesforce/apex/TrackingOrganizationController.completeCommit';
import createBranchActivity from '@salesforce/apex/TrackingOrganizationController.createBranchActivity';
import integrateWithExternalServices from '@salesforce/apex/TrackingOrganizationController.integrateWithExternalServices';

import JSZIP from '@salesforce/resourceUrl/jszipmaster';
import PAKO from '@salesforce/resourceUrl/Merge';

import { convertToJSON, TOAST_TYPE_SUCCESS, TOAST_TYPE_ERROR, TOAST_TYPE_WARNING } from 'c/trackingOrganizationHelper';

import { calculateCRCCodeForOrgComponents } from 'c/componentHelper';

import { X2JS } from 'c/xml2JsonHelper';

const FIRST_STAGE_LABEL = 'Select Branch';
const SECOND_STAGE_LABEL = 'Select Components';
const COMMIT_CHUNK_SIZE = 200;

const TABLE_SETTINGS = {
  isSupportSelect: true,
  recordsPerPage: 10,
  defaultSortField: 'componentName',
  paginationLabel: 'component',
  columnList: [
    {
      label: 'Component Name',
      field: 'componentName',
      isSorted: true,
      size: 3,
      type: 'string'
    },
    {
      label: 'Component Type',
      field: 'componentType',
      isSorted: true,
      size: 2,
      type: 'string'
    },
    {
      label: 'Changed By',
      field: 'changedBy',
      isSorted: true,
      size: 2,
      type: 'string'
    },
    {
      label: 'Changed On',
      field: 'changedOn',
      isSorted: true,
      size: 2,
      type: 'date'
    }
  ],
  componentList: []
};

export default class OrgComponentToBranchModal extends LightningElement {
  @api organizationId;
  @api accessToken;
  @api selectedComponentIdList = [];
  @api selectedDeletedComponentIdList = [];

  @track repositoryOptionList = [];

  @track cannotBeCommittedTableSettings = {};
  @track conflictComponentTableSettings = {};
  @track safeComponentTableSettings = {};
  @track notCommittedComponentTableSettings = {};
  @track destructiveComponentTableSettings = {};

  cannotBeCommittedComponentList = [];
  conflictComponentList = [];
  safeComponentList = [];
  notCommittedComponentList = [];
  destructiveOrgComponentList = [];

  @track progress = 0;
  @track countCommittedComponents = 0;
  @track countComponentsToCommit = 0;

  branchId = '';
  @track organizationName = '';
  @track stageLabel = FIRST_STAGE_LABEL;
  @track repositoryId = '';
  @track modalClass = 'slds-modal__container';
  @track modalBodyClass = 'slds-modal__content slds-p-around_medium modal-body';

  @track isShowProgress = false;
  @track isLoading = true;
  @track isFirstStage = true;

  @track committedComponentIds = [];

  activeSections = [
    'cannotBeCommittedSection',
    'conflictSection',
    'safeSection',
    'notCommittedSection',
    'destructiveSection'
  ];

  get isShowCannotBeCommittedTable() {
    return !!this.cannotBeCommittedComponentList.length;
  }

  connectedCallback() {
    Promise.resolve()
      .then(() =>
        Promise.all([
          loadScript(this, JSZIP + '/jszip-master/dist/jszip.js'),
          loadScript(this, PAKO + '/Merge/pako.min.js')
        ])
      )
      .then(() => this.callGetCommitToBranchOptions())
      .then(() => (this.isLoading = false))
      .catch((e) => {
        console.log('--- connectedCallback error', e);
        this.isLoading = false;
        this.showToast(e, TOAST_TYPE_ERROR);
      });
  }

  callGetCommitToBranchOptions() {
    return new Promise((resolve, reject) => {
      try {
        getCommitToBranchOptions({ dataMap: { organizationId: this.organizationId } })
          .then((result) => convertToJSON(result))
          .then((commitToBranchOptions) => {
            this.repositoryOptionList = commitToBranchOptions.repositoryOptionList;
            this.organizationName = commitToBranchOptions.organizationName;
            if (this.repositoryOptionList.length) {
              this.repositoryId = this.repositoryOptionList[0].value;
            }
            resolve();
          })
          .catch((e) => {
            console.log('--- error callGetCommitToBranchOptions', e);
            reject(e);
          });
      } catch (e) {
        console.log('--- error callGetCommitToBranchOptions', e);
        reject(e);
      }
    });
  }

  callGetAttachmentsBody(attachmentInfoList) {
    return new Promise((resolve, reject) => {
      try {
        const chunkList = [];
        let size = 0;

        const attachmentIdSet = new Set();
        attachmentInfoList.forEach((attachmentInfo) => {
          if (attachmentInfo.size >= 2700000 && attachmentInfo.size < 5700000) {
            chunkList.push(Array.from(attachmentIdSet));
            attachmentIdSet.clear();
            attachmentIdSet.add(attachmentInfo.id);
            chunkList.push(Array.from(attachmentIdSet));
            attachmentIdSet.clear();
            size = 0;
          } else {
            if (size + attachmentInfo.size < 2700000) {
              size += attachmentInfo.size;
              attachmentIdSet.add(attachmentInfo.id);
            } else {
              chunkList.push(Array.from(attachmentIdSet));
              attachmentIdSet.clear();
              attachmentIdSet.add(attachmentInfo.id);
              size = attachmentInfo.size;
            }
          }
        });

        if (attachmentIdSet.size) {
          chunkList.push(Array.from(attachmentIdSet));
        }

        const promiseList = [];
        let countProcessedChunks = 0;
        chunkList.forEach((attachmentIdList) => {
          const promise = Promise.resolve()
            .then(() => getAttachmentsBody({ dataMap: { attachmentIdListJson: JSON.stringify(attachmentIdList) } }))
            .then((attachmentBodyList) => {
              attachmentBodyList.forEach((attachmentWithBody) => {
                const attachment = attachmentInfoList.find(
                  (attachmentWithOutBody) => attachmentWithOutBody.id === attachmentWithBody.id
                );
                attachment.body = attachmentWithBody.body;
                attachment.componentType = attachmentWithBody.componentType;
              });
              countProcessedChunks++;
              this.progress = (countProcessedChunks / chunkList.length) * 45 + 15;
              return Promise.resolve();
            })
            .catch((e) => {
              console.log('--- getAttachmentsBody error', e);
              this.showToast(e, TOAST_TYPE_ERROR);
              countProcessedChunks++;
            });
          promiseList.push(promise);
        });
        Promise.all(promiseList)
          .then(() => resolve(attachmentInfoList))
          .catch((e) => {
            console.log('--- error callGetAttachmentsBody', e);
            reject(e);
          });
      } catch (e) {
        console.log('--- error callGetAttachmentsBody', e);
        reject(e);
      }
    });
  }

  handleLookupSearch(event) {
    const lookupElement = event.target;

    searchBranchLookup({
      dataMap: { searchTerm: event.detail.searchTerm ? event.detail.searchTerm : '', repositoryId: this.repositoryId }
    })
      .then((results) => lookupElement.setSearchResults(JSON.parse(results)))
      .catch((e) => {
        console.log('--- error handleLookupSearch', e);
        this.showToast(e, TOAST_TYPE_ERROR);
      });
  }

  handleChangeRepository(event) {
    this.repositoryId = event.detail.value;
    const target = this.template.querySelector('c-custom-lookup');
    const searchTerm = target.getSearchTerm();
    this.handleLookupSearch({ target, detail: { searchTerm } });
  }

  async handleContinueCommitToBranch() {
    if (this.isFirstStage) {
      this.handleFirstStage();
    } else {
      try {
        this.progress = 0;
        const selectedComponentIdList = [];
        const selectedComponentList = [];

        const destructiveTable = this.template.querySelector('[data-id="destructive"]');
        if (destructiveTable) {
          selectedComponentList.push(...destructiveTable.getSelectedComponents());
        }
        selectedComponentList.forEach((component) => (component.isDestructive = true));

        const commitComponentList = this.template.querySelectorAll('[data-id="component"]');
        if (commitComponentList && commitComponentList.length) {
          commitComponentList.forEach((table) => selectedComponentIdList.push(...table.getSelectedComponentIds()));
        }

        if (!selectedComponentIdList.length && !selectedComponentList.length) {
          this.showToast(`Please select least one component.`, TOAST_TYPE_WARNING);
        } else {
          this.isLoading = true;

          selectedComponentList.push(
            ...this.conflictComponentList.filter((component) => selectedComponentIdList.includes(component.id))
          );
          selectedComponentList.push(
            ...this.safeComponentList.filter((component) => selectedComponentIdList.includes(component.id))
          );
          selectedComponentList.push(
            ...this.notCommittedComponentList.filter((component) => selectedComponentIdList.includes(component.id))
          );

          this.countComponentsToCommit = selectedComponentList.length;
          this.isShowProgress = true;

          const chunkList = selectedComponentList.reduce(
            (chunkList, currentValue) => {
              const lastChunk = chunkList.slice(-1)[0];
              lastChunk.length >= COMMIT_CHUNK_SIZE ? chunkList.push([currentValue]) : lastChunk.push(currentValue);
              return chunkList;
            },
            [[]]
          );

          let promise = prepareToCommit({ branchId: this.branchId });
          let processedChunksCount = 0;
          chunkList.forEach((chunk) => {
            if (chunk.length) {
              const commitToBranchWrapper = {
                orgComponentIdToDataMap: {},
                orgComponentIdList: chunk.map((component) => component.id),
                attachmentIdList: chunk.map((component) => component.attachmentId),
                organizationId: this.organizationId,
                organizationName: this.organizationName,
                branchId: this.branchId,
                destructiveChangeList: []
              };

              chunk.forEach(({ componentType, componentName, crc32, attachmentId, isDestructive, isPostDeploy }) => {
                if (!isDestructive) {
                  commitToBranchWrapper.orgComponentIdToDataMap[`${componentType}#${componentName}`] = {
                    crc32,
                    attachmentId
                  };
                } else {
                  commitToBranchWrapper.destructiveChangeList.push({ componentType, componentName, isPostDeploy });
                }
              });

              promise = promise
                .then(() => commitToBranch({ commitToBranchWrapperJson: JSON.stringify(commitToBranchWrapper) }))
                .then((committedComponentIds) => {
                  processedChunksCount++;
                  this.countCommittedComponents += chunk.length;
                  this.progress = (processedChunksCount / chunkList.length) * 100;
                  this.committedComponentIds = JSON.parse(committedComponentIds);
                  return Promise.resolve();
                });
            }
          });

          promise
            .then(() =>
              createBranchActivity({
                //Create branch activity (add components from org)
                dataMap: {
                  type: 'commitToBranch',
                  organizationId: this.organizationId,
                  branchId: this.branchId,
                  idsList: JSON.stringify(selectedComponentIdList)
                }
              })
            )
            .then(() =>
              integrateWithExternalServices({
                //Invoke source analyzer
                dataMap: {
                  branchId: this.branchId,
                  idsList: JSON.stringify(this.committedComponentIds)
                }
              })
            )
            .then(() =>
              completeCommit({
                branchId: this.branchId
              })
            )
            .then(() => this.redirectToBranch())
            .catch((e) => {
              this.isLoading = false;
              this.isShowProgress = false;
              console.log('--- error commitToBranch', e);
              this.showToast(e, TOAST_TYPE_ERROR);
              return completeCommit({ branchId: this.branchId });
            });
        }
      } catch (e) {
        this.isShowProgress = false;
        console.log('--- error handleContinueCommitToBranchSecondStage', e);
        this.showToast(e, TOAST_TYPE_ERROR);
      }
    }
  }

  handleFirstStage() {
    try {
      this.isShowProgress = true;
      this.progress = 0;
      const customLookup = this.template.querySelector('c-custom-lookup');

      if (!customLookup) {
        this.showToast('Lookup element not found.', TOAST_TYPE_ERROR);
        return;
      }

      const selectedBranchList = customLookup.getSelection();
      let branchName = customLookup.getSearchTerm();

      if (selectedBranchList && selectedBranchList.length) {
        this.branchId = selectedBranchList[0].id;
        branchName = selectedBranchList[0].title;
      }

      if (!this.branchId && !branchName) {
        this.showToast('Please select exist branch or input name for a new branch.', TOAST_TYPE_WARNING);
        return;
      }

      this.isLoading = true;
      Promise.resolve()
        .then(() =>
          checkCommitPermissions({
            dataMap: {
              organizationId: this.organizationId,
              repositoryId: this.repositoryId,
              branchName,
              branchId: this.branchId
            }
          })
        )
        .then((resultBranchId) => {
          this.progress = 5;
          this.branchId = resultBranchId;
          return Promise.resolve();
        })
        .then(() =>
          getOrgComponentsInfo({
            dataMap: {
              orgComponentIdListJson: JSON.stringify([
                ...this.selectedComponentIdList,
                ...this.selectedDeletedComponentIdList
              ])
            }
          })
        )
        .then((result) => {
          this.progress = 10;
          return convertToJSON(result);
        })
        .then((orgComponentList) => {
          const selectedComponentIdList = JSON.parse(JSON.stringify(this.selectedComponentIdList));
          const selectedDeletedComponentIdList = JSON.parse(JSON.stringify(this.selectedDeletedComponentIdList));
          const commitOrgComponentList = orgComponentList.filter((comp) => selectedComponentIdList.includes(comp.id));
          this.destructiveOrgComponentList = orgComponentList.filter((comp) =>
            selectedDeletedComponentIdList.includes(comp.id)
          );
          if (commitOrgComponentList.length) {
            return this.getOrgComponentsWithAttachments(commitOrgComponentList)
              .then((orgComponentList) => {
                this.progress = 60;
                return orgComponentList.length ? calculateCRCCodeForOrgComponents(orgComponentList) : Promise.resolve();
              })
              .then((orgComponentList) => {
                this.progress = 80;
                return this.callCompareOrgComponentsAndBranchComponents(this.branchId, orgComponentList);
              });
          } else {
            return Promise.resolve();
          }
        })
        .then(() => this.showDestructiveChangesTable())
        .then(() => this.openSecondStage())
        .catch((e) => {
          console.log('--- handleFirstStage error', e);
          this.isLoading = false;
          this.isShowProgress = false;
          this.showToast(e, TOAST_TYPE_ERROR);
        });
    } catch (e) {
      console.log('--- error handleFirstStage', e);
      this.isShowProgress = false;
      this.showToast(e, TOAST_TYPE_ERROR);
    }
  }

  openSecondStage() {
    this.progress = 100;
    this.isFirstStage = false;
    this.stageLabel = SECOND_STAGE_LABEL;
    this.modalClass += ' second-stage-modal';
    this.modalBodyClass = this.modalBodyClass.replace('modal-body', 'second-stage-modal-body');
    this.isLoading = false;
    this.isShowProgress = false;
  }

  getOrgComponentsWithAttachments(orgComponentList) {
    return new Promise((resolve, reject) => {
      try {
        Promise.resolve()
          .then(() =>
            getAttachmentsInfo({
              dataMap: { attachmentIdListJson: JSON.stringify(orgComponentList.map((comp) => comp.attachmentId)) }
            })
          )
          .then((result) => convertToJSON(result))
          .then((attachmentInfoList) => {
            this.progress = 15;
            return this.callGetAttachmentsBody(attachmentInfoList);
          })
          .then((attachmentList) => {
            attachmentList.forEach((attachmentInfo) => {
              const orgComponent = orgComponentList.find(
                (orgComponent) => attachmentInfo.id === orgComponent.attachmentId
              );
              orgComponent.body = attachmentInfo.body;
              orgComponent.attachmentDescription = attachmentInfo.description;
              orgComponent.attachmentParentId = attachmentInfo.parentId;
            });
            resolve(orgComponentList);
          })
          .catch((e) => {
            console.log('--- getOrgComponentsWithAttachments error', e);
            this.showToast(e, TOAST_TYPE_ERROR);
            reject(e);
          });
      } catch (e) {
        console.log('--- getOrgComponentsWithAttachments error', e);
        this.showToast(e, TOAST_TYPE_ERROR);
      }
    });
  }

  async redirectToBranch() {
    let redirectUrl = '/' + this.branchId;

    try {
      const mergeSetName = await insertMergeSetAttachment({
        dataMap: {
          branchId: this.branchId,
          idsList: JSON.stringify(this.committedComponentIds)
        }
      });

      const pipelineOptionMap = await getBranchPipelineInfo({ dataMap: { branchId: this.branchId } });

      if (pipelineOptionMap) {
        redirectUrl = `${pipelineOptionMap.pipelinePageUrl}?id=${this.branchId}&pipeId=${pipelineOptionMap.Id}`;

        if (!pipelineOptionMap.isFullDeploy) {
          redirectUrl += `&mergeSetName=${mergeSetName}`;
        }
      }
    } catch (e) {
      console.log('--- redirectToBranch error', e);
    }
    window.open(redirectUrl, '_self');
  }

  callCompareOrgComponentsAndBranchComponents(branchId, orgComponentList) {
    return new Promise((resolve, reject) => {
      try {
        const dataMap = {};
        orgComponentList.forEach((component) => (dataMap[component.id] = component.crc32));
        Promise.resolve()
          .then(() =>
            compareOrgComponentsAndBranchComponents({
              dataMap: {
                organizationId: this.organizationId,
                branchId,
                orgComponentIdToCrcCodeMapJson: JSON.stringify(dataMap)
              }
            })
          )
          .then((result) => {
            const compareResult = JSON.parse(result);
            const cannotBeCommittedComponentList = [];
            const conflictComponentList = [];
            const safeComponentList = [];
            const notCommittedComponentList = [];

            orgComponentList.forEach((component) => {
              const historyIdSafe = compareResult.safeCommit[component.id];
              const historyIdConflict = compareResult.conflictCommit[component.id];
              const notCommit = compareResult.notCommitList.find((item) => item.id === component.id);

              if (historyIdSafe) {
                const autoResolved = historyIdSafe !== '0' ? 'AutoResolved' : '';
                safeComponentList.push({ ...component, historyId: historyIdSafe, autoResolved });
              } else if (historyIdConflict) {
                conflictComponentList.push({ ...component, historyId: historyIdConflict });
              } else if (notCommit) {
                notCommittedComponentList.push({ ...component, reason: notCommit.reason });
              }
            });

            if (cannotBeCommittedComponentList.length) {
              this.cannotBeCommittedTableSettings = JSON.parse(JSON.stringify(TABLE_SETTINGS));
              this.cannotBeCommittedTableSettings.isSupportSelect = false;
              this.cannotBeCommittedTableSettings.columnList.push({
                label: 'Reason',
                field: 'reason',
                isSorted: true,
                size: 3,
                type: 'string'
              });
              this.cannotBeCommittedTableSettings.componentList = cannotBeCommittedComponentList.map((component) => {
                return {
                  id: component.id,
                  changedBy: component.changedBy,
                  changedOn: component.changedOn,
                  componentName: component.componentName,
                  componentType: component.componentType,
                  reason: 'Component size is too large'
                };
              });
              this.cannotBeCommittedComponentList = cannotBeCommittedComponentList;
            }

            this.conflictComponentTableSettings = JSON.parse(JSON.stringify(TABLE_SETTINGS));
            this.conflictComponentTableSettings.columnList.push({
              label: 'Compare',
              field: 'conflict',
              isSorted: false,
              size: 1,
              type: 'action',
              //
              style: 'color: red;'
            });

            this.conflictComponentTableSettings.componentList = conflictComponentList.map((component) => {
              return {
                id: component.id,
                changedBy: component.changedBy,
                changedOn: component.changedOn,
                componentName: component.componentName,
                componentType: component.componentType,
                conflict: 'Conflict'
              };
            });

            this.safeComponentTableSettings = JSON.parse(JSON.stringify(TABLE_SETTINGS));
            this.safeComponentTableSettings.columnList.push({
              label: 'Compare',
              field: 'autoResolved',
              isSorted: false,
              size: 1,
              type: 'action',
              //
              style: 'color: green;'
            });

            this.safeComponentTableSettings.componentList = safeComponentList.map((component) => {
              return {
                id: component.id,
                changedBy: component.changedBy,
                changedOn: component.changedOn,
                componentName: component.componentName,
                componentType: component.componentType,
                autoResolved: component.autoResolved
              };
            });

            this.notCommittedComponentTableSettings = JSON.parse(JSON.stringify(TABLE_SETTINGS));
            this.notCommittedComponentTableSettings.columnList.push({
              label: 'Reason',
              field: 'reason',
              isSorted: true,
              size: 3,
              type: 'string'
            });

            this.notCommittedComponentTableSettings.componentList = notCommittedComponentList.map((component) => {
              return {
                id: component.id,
                changedBy: component.changedBy,
                changedOn: component.changedOn,
                componentName: component.componentName,
                componentType: component.componentType,
                reason: component.reason
              };
            });

            this.conflictComponentList = conflictComponentList;
            this.safeComponentList = safeComponentList;
            this.notCommittedComponentList = notCommittedComponentList;

            resolve();
          })
          .catch((e) => {
            console.log('--- callCompareOrgComponentsAndBranchComponents error', e);
            reject(e);
          });
      } catch (e) {
        console.log('--- callCompareOrgComponentsAndBranchComponents error', e);
        reject(e);
      }
    });
  }

  showDestructiveChangesTable() {
    if (this.destructiveOrgComponentList.length) {
      this.destructiveComponentTableSettings = JSON.parse(JSON.stringify(TABLE_SETTINGS));
      this.destructiveComponentTableSettings.columnList.push({
        label: 'Is Post Destructive',
        field: 'isPostDeploy',
        isSorted: false,
        size: 2,
        type: 'boolean'
      });
      this.destructiveComponentTableSettings.componentList = this.destructiveOrgComponentList.map((component) => {
        return {
          id: component.id,
          changedBy: component.changedBy,
          changedOn: component.changedOn,
          componentName: component.componentName,
          componentType: component.componentType,
          isPostDeploy: false
        };
      });
    }
  }

  handleSelectRepository(event) {
    this.repositoryId = event.detail.value;
  }

  handleCloseModal() {
    if (this.isShowProgress) {
      this.showToast('The window cannot be closed while the process is running.', TOAST_TYPE_WARNING);
    } else {
      this.dispatchEvent(new CustomEvent('close_modal'));
    }
  }

  handleConflict(event) {
    try {
      const sourceId = event.detail.id;
      const component = [...this.conflictComponentList, ...this.safeComponentList].find((item) => item.id === sourceId);
      const historyId = component.historyId;

      getHistoryComparisonUrl()
        .then((url) =>
          window.open(`${url}?fromMerge=fromLatestCommit&branchCompHisId=${historyId}&metaId=${sourceId}`, '_blank')
        )
        .catch((e) => {
          console.log('--- handleConflict error', e);
          this.showToast(e, TOAST_TYPE_ERROR);
        });
    } catch (e) {
      console.log('--- handleConflict error', e);
      this.showToast(e, TOAST_TYPE_ERROR);
    }
  }

  showToast(message, type) {
    if (type === TOAST_TYPE_ERROR) {
      message = utils.getErrorInformation(this, message);
    }

    const component = this.isClassic ? 'c-custom-toast-classic' : 'c-custom-toast';
    this.template.querySelector(component).showToast(message, type);
  }
}