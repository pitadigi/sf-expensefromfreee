public with sharing class pdExpenseFromFreee {
    /**
    * 取引(支出)を取得する
     */
    public static void getExpenseInfo(Integer months) {
        pdExpenseFromFreee.getExpenseInfoByBaseDate(null, months);
    }

    /**
    * 取引(支出)を取得する(基準日指定)
     */
    @future(callout=true) 
    public static void getExpenseInfoByBaseDate(Date baseDate,Integer months) {
        // 会社情報を取得する
        Integer companyId = getCompany();

        // 勘定科目情報を取得する
        Map<Integer, pdAccountInfo> mapAccountInfo = getAccountInfo(companyId);

        Date targetDate = (baseDate == null) ? Date.today().toStartOfMonth() : baseDate.toStartOfMonth();
        List<Expense__c> lstExpense = new List<Expense__c>();
        List<Income__c> lstIncome = new List<Income__c>();
        List<Expense__c> lstExpenseDeleteAll = new List<Expense__c>();
        List<Income__c> lstIncomeDeleteAll = new List<Income__c>();
        for(Integer i=0 ; i<months ; i++){
            Date startDate = targetDate.addMonths(i * (-1));
            Date endDate = startDate.addMonths(1).addDays(-1);

            List<Expense__c> lstExpenseDelete = [SELECT Id FROM Expense__c WHERE IssueDate__c >= :startDate AND IssueDate__c <= :endDate];
            if (lstExpenseDelete.size() != 0) {
                lstExpenseDeleteAll.addAll(lstExpenseDelete);
            }
            List<Income__c> lstIncomeDelete = [SELECT Id FROM Income__c WHERE IssueDate__c >= :startDate AND IssueDate__c <= :endDate];
            if (lstIncomeDelete.size() != 0) {
                lstIncomeDeleteAll.addAll(lstIncomeDelete);
            }

            lstExpense.addAll(getExpense(companyId, mapAccountInfo, startDate, endDate));
            lstIncome.addAll(getIncome(companyId, mapAccountInfo, startDate, endDate));

            // 振替伝票情報を収入、経費に反映する
            getManualJournals(companyId, mapAccountInfo, startDate, endDate, lstIncome, lstExpense);
        }

        // 明細データを削除する
        delete lstExpenseDeleteAll;
        delete lstIncomeDeleteAll;

        insert lstExpense;
        insert lstIncome;
    }

    /**
    * 会社情報を取得する
     */
    private static Integer getCompany() {    
        // 会社情報を取得する
        Http http = new Http();
        String path = 'callout:Freee/companies';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(path);
        req.setMethod('GET');

        HttpResponse res = http.send(req);
        // 会社情報が返ってきたらIIDと名称を設定する
        if (res.getStatusCode() == 200) {
            Map<String, Object> mapCompany = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            List<Object> lstCompany = (List<Object>)mapCompany.get('companies');
            if (lstCompany.size() == 0) {
                throw new OtherException('会社情報が取得できません');
            }
            else {
                return (Integer)((Map<String, Object>)lstCompany[0]).get('id');
            }
        }
        // エラーで返ってきたら例外をスローする
        else {
            throw new OtherException(getApiErrorMessage(res.getBody()));
        }
    }

    /**
    * 勘定科目情報を取得する
     */
    private static Map<Integer, pdAccountInfo> getAccountInfo(Integer companyId) {
        // 勘定科目情報を取得する
        Http http = new Http();
        String path = 'callout:Freee/account_items';
        String parameters = 'company_id=' + companyId;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(path + '?' + parameters);
        req.setMethod('GET');

        HttpResponse res = http.send(req);

        // 正常に返って来たらオブジェクトに設定する
        Map<Integer, pdAccountInfo> mapAccoutList = new Map<Integer, pdAccountInfo>();
        if (res.getStatusCode() == 200) {
            Map<String, Object> mapBody = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            List<Object> lstBody = (List<Object>)mapBody.get('account_items');
            for(Object item : lstBody) {
                Map<String, Object> mapItem = (Map<String, Object>)item;
                pdAccountInfo accountInfo = new pdAccountInfo();
                accountInfo.Name = (String)mapItem.get('name');
                accountInfo.Category = (String)mapItem.get('account_category');
                mapAccoutList.put((Integer)mapItem.get('id'), accountInfo);
            }
        }
        else {
            throw new OtherException(getApiErrorMessage(res.getBody()));
        }

        return mapAccoutList;
    }

    /**
    * 経費明細を取得する
    */
    private static List<Expense__c> getExpense(Integer companyId, Map<Integer, pdAccountInfo> mapAccountInfo, Date startDate, Date endDate) {
        List<Expense__c> lstExpense = new List<Expense__c>();
        List<Object> lstDeals = getDeals('expense', companyId, startDate, endDate);
        for(Object deal : lstDeals) {
            Map<String, Object> mapDeal = (Map<String, Object>)deal;
            List<Object> lstDetail = (List<Object>)mapDeal.get('details');
            for(Object detail : lstDetail) {
                Map<String, Object> mapDetail = (Map<String, Object>)detail;

                // 経費明細データを作成する
                Expense__c expense = new Expense__c();
                // ID
                expense.Name += String.valueOf((Long)mapDetail.get('id'));
                // 計上日
                expense.AccountDate__c = Date.valueOf((String)mapDeal.get('issue_date'));
                // 発生日
                expense.IssueDate__c = Date.valueOf((String)mapDeal.get('issue_date'));
                // 勘定科目
                expense.AccountItem__c = getAccountName(mapAccountInfo, (Integer)mapDetail.get('account_item_id'));
                // 勘定科目カテゴリ
                expense.Category__c = getAccountCategory(mapAccountInfo, (Integer)mapDetail.get('account_item_id'));
                // 金額
                expense.Amount__c = (Long)mapDetail.get('amount');
                // 備考
                String description = (String)mapDetail.get('description');
                if (description == null) {
                    description = '';
                }
                expense.Description__c = description.replace(',', '、').replace('¥"', '”');

                lstExpense.add(expense);
            }
        }
        
        return lstExpense;
    }

    /**
    * 収入明細を取得する
    */
    private static List<Income__c> getIncome(Integer companyId, Map<Integer, pdAccountInfo> mapAccountInfo, Date startDate, Date endDate) {
        List<Income__c> lstIncome = new List<Income__c>();
        List<Object> lstDeals = getDeals('income', companyId, startDate, endDate);
        for(Object deal : lstDeals) {
            Map<String, Object> mapDeal = (Map<String, Object>)deal;
            List<Object> lstDetail = (List<Object>)mapDeal.get('details');
            for(Object detail : lstDetail) {
                Map<String, Object> mapDetail = (Map<String, Object>)detail;

                // 収入明細データを作成する
                Income__c income = new Income__c();
                // ID
                income.Name += String.valueOf((Long)mapDetail.get('id'));
                // 計上日
                income.AccountDate__c = Date.valueOf((String)mapDeal.get('issue_date'));
                // 発生日
                income.IssueDate__c = Date.valueOf((String)mapDeal.get('issue_date'));
                // 勘定科目
                income.AccountItem__c = getAccountName(mapAccountInfo, (Integer)mapDetail.get('account_item_id'));
                // 勘定科目カテゴリ
                income.Category__c = getAccountCategory(mapAccountInfo, (Integer)mapDetail.get('account_item_id'));
                // 金額
                income.Amount__c = (Long)mapDetail.get('amount');
                // 備考
                String description = (String)mapDetail.get('description');
                if (description == null) {
                    description = '';
                }
                income.Description__c = description.replace(',', '、').replace('¥"', '”');

                lstIncome.add(income);
            }
        }
        
        return lstIncome;
    }

    /**
     * 取引情報をfreeeから取得する
     */
    private static List<Object> getDeals(String type, Integer companyId, Date startDate, Date endDate) {
        Http http = new Http();
        String path = 'callout:Freee/deals';
        String parameters = 'company_id=' + companyId;
        parameters += '&type=' + type;
        parameters += '&start_issue_date=' + startDate.format().replace('/', '-');
        parameters += '&end_issue_date=' + endDate.format().replace('/', '-');
        parameters += '&limit=100';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(path + '?' + parameters);
        req.setMethod('GET');

        HttpResponse res = http.send(req);

        List<Object> lstDeals = new List<Object>();
        if(res.getStatusCode() == 200) {
            Map<String, Object> mapBody = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            lstDeals = (List<Object>)mapBody.get('deals');
        }

        return lstDeals;
    }

    /**
     * 振替伝票情報をfreeeから取得する
     * 取得した振替伝票の貸借を以下のように処理する
     * 借方: 経費明細として追加する
     * 貸方: 収入明細として追加する
     */
    private static void getManualJournals(Integer companyId, Map<Integer, pdAccountInfo> mapAccountInfo, Date startDate, Date endDate, List<Income__c> lstIncome, List<Expense__c> lstExpense) {
        Http http = new Http();
        String path = 'callout:Freee/manual_journals';
        String parameters = 'company_id=' + companyId;
        parameters += '&start_issue_date=' + startDate.format().replace('/', '-');
        parameters += '&end_issue_date=' + endDate.format().replace('/', '-');
        parameters += '&limit=100';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(path + '?' + parameters);
        req.setMethod('GET');

        HttpResponse res = http.send(req);

        if(res.getStatusCode() == 200) {
            Map<String, Object> mapBody = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            List<Object> lstManualJournal = (List<Object>)mapBody.get('manual_journals');
            for(Object manualJournal : lstManualJournal) {
                Map<String, Object> mapManualJournal = (Map<String, Object>)manualJournal;
                List<Object> lstDetail = (List<Object>)mapManualJournal.get('details');
                for(Object detail : lstDetail) {
                    Map<String, Object> mapDetail = (Map<String, Object>)detail;

                    if ((String)mapDetail.get('entry_side') == 'credit') {
                        // 収入明細データを作成する
                        Income__c income = new Income__c();
                        // ID
                        income.Name += String.valueOf((Long)mapDetail.get('id'));
                        // 計上日
                        income.AccountDate__c = Date.valueOf((String)mapManualJournal.get('issue_date'));
                        // 発生日
                        income.IssueDate__c = Date.valueOf((String)mapManualJournal.get('issue_date'));
                        // 勘定科目
                        income.AccountItem__c = getAccountName(mapAccountInfo, (Integer)mapDetail.get('account_item_id'));
                        // 勘定科目カテゴリ
                        income.Category__c = getAccountCategory(mapAccountInfo, (Integer)mapDetail.get('account_item_id'));
                        // 金額
                        income.Amount__c = (Long)mapDetail.get('amount');
                        // 備考
                        String description = (String)mapDetail.get('description');
                        if (description == null) {
                            description = '';
                        }
                        income.Description__c = description.replace(',', '、').replace('¥"', '”');

                        lstIncome.add(income);
                    }
                    else {
                        // 経費明細データを作成する
                        Expense__c expense = new Expense__c();
                        // ID
                        expense.Name += String.valueOf((Long)mapDetail.get('id'));
                        // 計上日
                        expense.AccountDate__c = Date.valueOf((String)mapManualJournal.get('issue_date'));
                        // 発生日
                        expense.IssueDate__c = Date.valueOf((String)mapManualJournal.get('issue_date'));
                        // 勘定科目
                        expense.AccountItem__c = getAccountName(mapAccountInfo, (Integer)mapDetail.get('account_item_id'));
                        // 勘定科目カテゴリ
                        expense.Category__c = getAccountCategory(mapAccountInfo, (Integer)mapDetail.get('account_item_id'));
                        // 金額
                        expense.Amount__c = (Long)mapDetail.get('amount');
                        // 備考
                        String description = (String)mapDetail.get('description');
                        if (description == null) {
                            description = '';
                        }
                        expense.Description__c = description.replace(',', '、').replace('¥"', '”');

                        lstExpense.add(expense);
                    }
                }
            }
        }
    }

    /**
    * 勘定科目リストから指定IDの勘定科目名を返す
     */
    private static String getAccountName(Map<Integer, pdAccountInfo> mapAccountInfo, Integer Id) {
        return mapAccountInfo.get(Id).Name;
    }

    /**
    * 勘定科目リストから指定IDの勘定科目カテゴリを返す
     */
    private static String getAccountCategory(Map<Integer, pdAccountInfo> mapAccountInfo, Integer Id) {
        return mapAccountInfo.get(Id).Category;
    }

    /**
    * エラーメッセージを設定する
     */
    private static String getApiErrorMessage(String body) {
        System.debug(body);
        String errorMessage = 'Freee APIでエラーが発生しました\r\n';
        if (body != null && body.length() != 0) {
            Map<String, Object> mapError = (Map<String, Object>)JSON.deserializeUntyped(body);
            List<Object> lstError = (List<Object>)(mapError.get('errors'));
            for(Object mapErrorContent : lstError) {
                List<Object> lstMessage = (List<Object>)((Map<String, Object>)mapErrorContent).get('messages');
                for(Object message : lstMessage) {
                    errorMessage += message.toString() + '\r\n';
                }
            }
        }

        return errorMessage;
    }

    public virtual class BaseException extends Exception {}
    public class OtherException extends BaseException {}

}
