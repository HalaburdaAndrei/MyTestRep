import updateComponentsWithDependencies from '@salesforce/apex/TrackingOrganizationController.updateComponentsWithDependencies';





import { X2JS } from 'c/xml2JsonHelper';



import { Beautify } from 'c/beautifyHelper';

const innerSRCJSONMap = {
  CustomLabel: 'CustomLabels',
  CustomField: 'CustomObject',
  ListView: 'CustomObject',
  CompactLayout: 'CustomObject',
  WebLink: 'CustomObject',
  RecordType: 'CustomObject',
  FieldSet: 'CustomObject',
  ValidationRule: 'CustomObject',
  BusinessProcess: 'CustomObject',
  SharingReason: 'CustomObject',
  AssignmentRule: 'AssignmentRules',
  AutoResponseRule: 'AutoResponseRules',
  WorkflowTask: 'Workflow',
  WorkflowOutboundMessage: 'Workflow',
  WorkflowFieldUpdate: 'Workflow',
  WorkflowKnowledgePublish: 'Workflow',
  WorkflowAlert: 'Workflow',
  WorkflowRule: 'Workflow',
  SharingCriteriaRule: 'SharingRules',
  SharingGuestRule: 'SharingRules',
  SharingTerritoryRule: 'SharingRules',
  SharingOwnerRule: 'SharingRules',
  EscalationRule: 'EscalationRules',
  MatchingRule: 'MatchingRules',
  ManagedTopic: 'ManagedTopics',
  BotVersion: 'Bot'
};

const innerSRCItemMap = {
  CustomLabel: 'labels',
  CustomField: 'fields',
  ListView: 'listViews',
  CompactLayout: 'compactLayouts',
  WebLink: 'webLinks',
  RecordType: 'recordTypes',
  FieldSet: 'fieldSets',
  ValidationRule: 'validationRules',
  BusinessProcess: 'businessProcesses',
  SharingReason: 'sharingReasons',
  AssignmentRule: 'assignmentRule',
  AutoResponseRule: 'autoResponseRule',
  WorkflowTask: 'tasks',
  WorkflowOutboundMessage: 'outboundMessages',
  WorkflowFieldUpdate: 'fieldUpdates',
  WorkflowKnowledgePublish: 'knowledgePublishes',
  WorkflowAlert: 'alerts',
  WorkflowRule: 'rules',
  SharingCriteriaRule: 'sharingCriteriaRules',
  SharingGuestRule: 'sharingGuestRules',
  SharingTerritoryRule: 'sharingTerritoryRules',
  SharingOwnerRule: 'sharingOwnerRules',
  EscalationRule: 'escalationRule',
  MatchingRule: 'matchingRules',
  ManagedTopic: 'managedTopic',
  BotVersion: 'botVersions'
};

const innerXMLHeaderMap = {
  CustomLabel: '<?xml version="1.0" encoding="UTF-8"?><CustomLabels xmlns="http://soap.sforce.com/2006/04/metadata">',
  AssignmentRule:
    '<?xml version="1.0" encoding="UTF-8"?><AssignmentRules xmlns="http://soap.sforce.com/2006/04/metadata">',
  AutoResponseRule:
    '<?xml version="1.0" encoding="UTF-8"?><AutoResponseRules xmlns="http://soap.sforce.com/2006/04/metadata">',
  WorkflowTask: '<?xml version="1.0" encoding="UTF-8"?><Workflow xmlns="http://soap.sforce.com/2006/04/metadata">',
  WorkflowOutboundMessage:
    '<?xml version="1.0" encoding="UTF-8"?><Workflow xmlns="http://soap.sforce.com/2006/04/metadata">',
  WorkflowFieldUpdate:
    '<?xml version="1.0" encoding="UTF-8"?><Workflow xmlns="http://soap.sforce.com/2006/04/metadata">',
  WorkflowKnowledgePublish:
    '<?xml version="1.0" encoding="UTF-8"?><Workflow xmlns="http://soap.sforce.com/2006/04/metadata">',
  WorkflowAlert: '<?xml version="1.0" encoding="UTF-8"?><Workflow xmlns="http://soap.sforce.com/2006/04/metadata">',
  WorkflowRule: '<?xml version="1.0" encoding="UTF-8"?><Workflow xmlns="http://soap.sforce.com/2006/04/metadata">',
  SharingCriteriaRule:
    '<?xml version="1.0" encoding="UTF-8"?><SharingRules xmlns="http://soap.sforce.com/2006/04/metadata">',
  SharingGuestRule:
    '<?xml version="1.0" encoding="UTF-8"?><SharingRules xmlns="http://soap.sforce.com/2006/04/metadata">',
  SharingTerritoryRule:
    '<?xml version="1.0" encoding="UTF-8"?><SharingRules xmlns="http://soap.sforce.com/2006/04/metadata">',
  SharingOwnerRule:
    '<?xml version="1.0" encoding="UTF-8"?><SharingRules xmlns="http://soap.sforce.com/2006/04/metadata">',
  EscalationRule:
    '<?xml version="1.0" encoding="UTF-8"?><EscalationRules xmlns="http://soap.sforce.com/2006/04/metadata">',
  MatchingRule: '<?xml version="1.0" encoding="UTF-8"?><MatchingRules xmlns="http://soap.sforce.com/2006/04/metadata">',
  ManagedTopic: '<?xml version="1.0" encoding="UTF-8"?><ManagedTopics xmlns="http://soap.sforce.com/2006/04/metadata">',
  BotVersion: '<?xml version="1.0" encoding="UTF-8"?><Bot xmlns="http://soap.sforce.com/2006/04/metadata">',
  Other: '<?xml version="1.0" encoding="UTF-8"?><CustomObject xmlns="http://soap.sforce.com/2006/04/metadata">'
};

const componentTypeProcessFunctionMap = {
  Layout: layoutTypesProcessor,
  Profile: profileTypesProcessor,
  PermissionSet: profileTypesProcessor,
  AuraDefinitionBundle: bundleTypesProcessor,
  LightningComponentBundle: bundleTypesProcessor,
  ExperienceBundle: bundleTypesProcessor,
  WaveTemplateBundle: bundleTypesProcessor,
  DigitalExperience: bundleTypesProcessor,
  DigitalExperienceBundle: bundleTypesProcessor,
  CustomField: innerTypesProcessor,
  CustomLabel: innerTypesProcessor,
  CompactLayout: innerTypesProcessor,
  WebLink: innerTypesProcessor,
  RecordType: innerTypesProcessor,
  ListView: innerTypesProcessor,
  FieldSet: innerTypesProcessor,
  AssignmentRule: innerTypesProcessor,
  AutoResponseRule: innerTypesProcessor,
  ValidationRule: innerTypesProcessor,
  WorkflowTask: innerTypesProcessor,
  WorkflowOutboundMessage: innerTypesProcessor,
  WorkflowFieldUpdate: innerTypesProcessor,
  WorkflowKnowledgePublish: innerTypesProcessor,
  WorkflowAlert: innerTypesProcessor,
  WorkflowRule: innerTypesProcessor,
  SharingOwnerRule: innerTypesProcessor,
  SharingGuestRule: innerTypesProcessor,
  SharingTerritoryRule: innerTypesProcessor,
  SharingCriteriaRule: innerTypesProcessor,
  BusinessProcess: innerTypesProcessor,
  SharingReason: innerTypesProcessor,
  EscalationRule: innerTypesProcessor,
  MatchingRule: innerTypesProcessor,
  ManagedTopic: innerTypesProcessor,
  BotVersion: innerTypesProcessor
};

let beautify;

function layoutTypesProcessor(component) {
  const jszip = component.jszip;

  for (const filename in jszip.files) {
    if (filename === 'package.xml') {
      jszip.remove(filename);
      continue;
    }

    if (!filename.includes('/')) {
      continue;
    }

    const [type] = filename.split('/');

    if (type === 'layouts') {
      continue;
    }

    jszip.remove(filename);
  }

  component.body = jszip.generate({ type: 'base64' });
  component.isCroped = true;

  return otherComponentsProcessor(component);
}

function profileTypesProcessor(component) {

  const jszip = component.jszip;

  const validTypes = new Set(['profiles', 'permissionsets']);

  for (const filename in jszip.files) {
    if (filename === 'package.xml') {
      jszip.remove(filename);
      continue;
    }


    if (!filename.includes('/')) {
      continue;
    }

    const [type] = filename.split('/');

    if (validTypes.has(type)) {
      continue;
    }

    jszip.remove(filename);
  }

  let crc32List = [];

  Object.keys(jszip.files).forEach((fileName) => {
    if (fileName && (fileName.startsWith('profiles/') || fileName.startsWith('permissionsets/'))) {
      let fileData = jszip.files[fileName].asBinary();
      const crcWithData = getCrcWithData(fileData, { isCompress: true });
      if (crcWithData) {
        crc32List.push(crcWithData.crc32);
      }
    }
  });

  component.body = jszip.generate({ type: 'base64' });
  component.isCroped = true;

  delete component.jszip;

  return crc32List.join(' ');
}

function bundleTypesProcessor(component) {
  let crc32List = [];
  const jszip = component.jszip;

  const setToRemove = new Set();
  Object.keys(jszip.files)
    .sort()
    .forEach((fileName) => {
      const auraName = getAuraName(fileName, component.componentType);
      if (auraName && auraName === component.fileName) {
        const fileData = jszip.files[fileName].asBinary();
        const crcWithData = getCrcWithData(fileData);
        if (crcWithData) {
          crc32List.push(crcWithData.crc32);
        }
      } else {
        setToRemove.add(fileName);
      }
    });




  let crcCode = 0;

  if (crc32List.length) {
    crcCode = crc32List[0];
  }

  if (crc32List.length < 26) {
    for (let i = 1; i < crc32List.length; i++) {
      crcCode = Math.round((crc32List[i] + crcCode) / 2);
    }
  } else {
    for (let i = 1; i < crc32List.length; i++) {
      crcCode = Math.round(crc32List[i] + crcCode);
    }
    crcCode = Math.round(crcCode / crc32List.length);
  }

  setToRemove.forEach((type) => jszip.remove(type));
  component.body = jszip.generate({ type: 'base64' });
  delete component.jszip;

  return `${crcCode}`;
}

function innerTypesProcessor(component) {
  let crc32List = [];
  const jszip = component.jszip;

  const trueComponentsMap = {};
  Object.keys(jszip.files).forEach((fileName) => {
    if (
      fileName &&
      fileName.charAt(fileName.length - 1) !== '/' &&
      fileName !== 'package.xml' &&
      fileName !== 'undefined'
    ) {
      const childXMLMap = getChildXMLList(
        jszip.files[fileName].asText(),
        component.componentType,
        component.componentName
      );
      Object.keys(childXMLMap).forEach((name) => {
        trueComponentsMap[fileName] = childXMLMap[name];
        const crcWithData = getCrcWithData(childXMLMap[name], {
          isInnerType: true
        });
        if (crcWithData) {
          crc32List.push(crcWithData.crc32);
        }
      });
    }
  });

  Object.keys(trueComponentsMap).forEach((fileName) => jszip.file(fileName, trueComponentsMap[fileName]));

  component.body = jszip.generate({ type: 'base64' });
  component.isCroped = true;
  delete component.jszip;

  return crc32List.join(' ');
}

function getChildXMLList(xml, type, componentName) {
  componentName = componentName.includes('.') ? componentName.split('.')[1] : componentName;

  const childXMLMap = {};
  const x2js = new X2JS({
    useDoubleQuotes: true,
    stripWhitespaces: false,
    escapeMode: true
  });

  const jsonMap = {};
  const srcJson = x2js.xml_str2json(xml);



  const getBody = (tempJSON, type) => {
    return `<${innerSRCItemMap[type]}>${x2js.json2xml_str(JSON.parse(tempJSON))}</${innerSRCItemMap[type]}>`;
  };

  const getFooter = (tempJSON, type) => {
    return `</${innerSRCJSONMap[type]}>`;
  };

  if (srcJson) {
    const srcItemList = srcJson[innerSRCJSONMap[type]][innerSRCItemMap[type]];

    if (srcItemList) {
      if (srcItemList.fullName && srcItemList.fullName === componentName) {
        jsonMap[srcItemList.fullName] = JSON.stringify(srcItemList);
      } else {
        srcItemList.forEach((item) => {
          if (item.fullName === componentName) {
            jsonMap[item.fullName] = JSON.stringify(item);
          }
        });
      }
    }
  }


  Object.keys(jsonMap).forEach((name) => {
    const tempJSON = jsonMap[name];
    if (tempJSON) {
      const header = innerXMLHeaderMap[type] ? innerXMLHeaderMap[type] : innerXMLHeaderMap.Other;
      const body = getBody(tempJSON, type);
      const footer = getFooter(tempJSON, type);
      childXMLMap[name] = `${header}${body}${footer}`;
    }
  });
  return childXMLMap;
}

function otherComponentsProcessor(component) {
  const jszip = component.jszip;
  let crc32List = [];
  Object.keys(jszip.files).forEach((fileName) => {
    if (
      fileName &&
      fileName.charAt(fileName.length - 1) !== '/' &&
      fileName !== 'package.xml' &&
      fileName !== 'undefined' &&
      fileName === component.fileName
    ) {
      const fileData = jszip.files[fileName].asBinary();
      const crcWithData = getCrcWithData(fileData);
      if (crcWithData) {
        crc32List.push(crcWithData.crc32);
      }
    }
  });

  component.body = jszip.generate({ type: 'base64' });
  delete component.jszip;

  return crc32List.join(' ');
}

function getPosition(string, subString, index) {
  //function for getting INDEX of Substring in String.
  return string.split(subString, index).join(subString).length;
}

function getAuraName(name, tempComponentType) {
  if (!name) return;
  if (
    !name.startsWith('aura/') &&
    !name.startsWith('lwc/') &&
    !name.startsWith('experiences/') &&
    !name.startsWith('waveTemplates/') &&
    !name.startsWith('digitalExperiences/')
  )
    return;

  if (name.lastIndexOf('/') > 5 && name.lastIndexOf('/') !== name.length - 1) {

    let fullName;
    if (name.startsWith('digitalExperiences/')) {
      const position = tempComponentType == 'DigitalExperienceBundle' ? 3 : 5;
      fullName = name.slice(0, getPosition(name, '/', position));
    } else {
      fullName = name.slice(0, getPosition(name, '/', 2)); //name.lastIndexOf('/');
    }

    if (name.startsWith('experiences/') || name.startsWith('waveTemplates/')) {
      if (fullName.lastIndexOf('/') !== -1) {
        fullName = fullName.slice(0, fullName.lastIndexOf('/'));
      }
      return fullName;
    } else {
      return fullName;
    }
  }
}

function getCrcWithData(zipData, flags) {
  const crcWithData = {};
  const jsZip = new JSZip();

  if (zipData && flags && flags.isInnerType) {
    if (!beautify) {
      beautify = new Beautify();
    }
    zipData = beautify.xml(zipData);
  }

  crcWithData.crc32 = jsZip.crc32(zipData, 32);
  if (flags && flags.isCompress) {
    crcWithData.data = pako.deflate(zipData, { to: 'string' });
  } else {
    crcWithData.data = zipData;
  }

  return crcWithData;
}

function calculateCRCCodeForOrgComponents(componentList) {
  return new Promise((resolve, reject) => {
    try {
      componentList.forEach((component) => {
        component.jszip = new JSZip(component.body, { base64: true });

        if (componentTypeProcessFunctionMap[component.componentType]) {
          component.crc32 = componentTypeProcessFunctionMap[component.componentType].call(this, component);
        } else {
          component.crc32 = otherComponentsProcessor(component);
        }
      });

      let promise = Promise.resolve().then(() => componentList.forEach((component) => delete component.jszip));
      const dependencyComponents = componentList
        .filter((c) => c.isCroped)
        .map((c) => ({ attachmentId: c.attachmentId, body: c.body }));

      if (dependencyComponents.length) {
        const promises = dependencyComponents.map((dependencyComponent) =>
            updateComponentsWithDependencies({
              dependencyComponentJson: JSON.stringify(dependencyComponent)
            })
        );

        promise = promise.then(() => Promise.all(promises));
      }

      promise
        .then(() => componentList.forEach((component) => delete component.body))
        .then(() => {
          resolve(componentList);
        })
        .catch(reject);
    } catch (e) {
      reject(e);
    }
  });
}

export { calculateCRCCodeForOrgComponents, getChildXMLList};