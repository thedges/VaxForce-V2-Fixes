public without sharing class VaxForceBulkUploadController {
    @AuraEnabled
    public static String processBulkUpload(String strFileName, String base64Data, String baseURL)
    {
        Map<String, Object> resp = new Map<String, Object>();
        Map<String, Object> results = new Map<String, Object>();

        //////////////////////////
        // setup default values //
        //////////////////////////
        resp.put('status', 'SUCCESS');
        results.put('totalRows', 0);
        results.put('totalNew', 0);
        results.put('totalDup', 0);

        ////////////////////////////////////////////////////////
        // trigger bulk load email notifications              //
        // - this has to exist before any database operations //
        ////////////////////////////////////////////////////////
        HttpRequest req = new HttpRequest();
        req.setEndpoint(baseURL + '/VaxForce/services/apexrest/BulkLoadEmail');
        req.setMethod('GET');

        Http http = new Http();
        HTTPResponse res = http.send(req);

        /////////////////////////////////
        // parse bulk file and process //
        /////////////////////////////////
        base64Data = EncodingUtil.urlDecode(base64Data, 'UTF-8');
        String fileData = EncodingUtil.base64Decode(base64Data).toString();

        String[] dataLines = fileData.split('\n');
        System.debug('dataLines=' + dataLines);
        System.debug('dataLines[0]=' + dataLines[0]);

        //////////////////////////////////////////////////////
        // reject file that doesn't have correct header row //
        //////////////////////////////////////////////////////
        if (dataLines == null || dataLines.size() == 0 || dataLines[0] == null || dataLines[0].trim() != 'LastName,FirstName,Phone,Email,Job Function,Employer,Street,City,State,Zipcode,GUID')
        {
            resp.put('status', 'ERROR');
            resp.put('statusMsg', 'File format does not appear to be correct!');
        }
        else {
            /////////////////////////////////////////////////////////////////////////////////////
            // simulate loading data by actually doing an upsert but perform database rollback //
            /////////////////////////////////////////////////////////////////////////////////////
            Integer totalRows = 0;
            Integer totalNew = 0;
            Integer totalUpdated = 0;
            Integer totalErrors = 0;
            Integer msg = null;

            Id personAccountRecordTypeId =  Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('PersonAccounts').getRecordTypeId();

            // create list of accounts
            List<Account> acctList = new List<Account>();

            ///////////////////////////////////////////////////////////////////////
            // loop through each row of file and add PersonAccount to collection //
            ///////////////////////////////////////////////////////////////////////
            for (Integer i = 1; i < dataLines.size(); i++) {
                String[] csvRecordData = dataLines[i].split(',');

                Account acct = new Account();
                acct.LastName = csvRecordData[0];
                acct.FirstName = csvRecordData[1];
                acct.Phone = csvRecordData[2];
                acct.PersonEmail = csvRecordData[3];

                //acct.Name = csvRecordData[5];
                acct.PersonMailingStreet = csvRecordData[6];
                acct.PersonMailingCity = csvRecordData[7];
                acct.PersonMailingState = csvRecordData[8];
                acct.PersonMailingPostalcode = csvRecordData[9];
                acct.Unique_Id__c = csvRecordData[10];
                acct.RecordTypeId = personAccountRecordTypeId;

                acctList.add(acct);
            }

            System.debug(JSON.serializePretty(acctList));

            /////////////////
            // upsert data //
            /////////////////
            Schema.SObjectField ftoken = Account.Fields.Unique_Id__c;

            Savepoint sp = Database.setSavepoint();

            try {
                Database.UpsertResult[] srList = Database.upsert(acctList,ftoken,false);

                for (Database.UpsertResult sr : srList)
                {
                    totalRows++;

                    if (sr.isSuccess()) {
                        if (sr.isCreated())
                        {
                            totalNew++;
                        }
                        else {
                            totalUpdated++;
                        }
                    }
                    else
                    {
                        totalErrors++;
                        // Operation failed, so get all errors

                        for(Database.Error err : sr.getErrors()) {
                            System.debug('error has occurred.' + err.getStatusCode() + ': ' + err.getMessage());
                            System.debug('fields that affected this error: ' + err.getFields());

                        }

                    }
                }

                ///////////////////////////////////
                // rollback data even on success //
                ///////////////////////////////////
                Database.rollback(sp);

            } catch (Exception ex) {
                Database.rollback(sp);
            }

            results.put('totalRows', totalRows);
            results.put('totalNew', totalNew);
            results.put('totalUpdated', totalUpdated);
            results.put('totalErrors', totalErrors);
            results.put('msg', msg);
        }

        resp.put('metrics', results);

        return JSON.serializePretty(resp);
    }
}