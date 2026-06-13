@isTest(SeeAllData=true)
private class pdExpenseFromFreee_test {
    @isTest
    static void getExpenseInfo_test() {
        Test.setMock(HttpCalloutMock.class, new pdExpenseFromFreeeCalloutMock());

        pdExpenseFromFreee.getExpenseInfo(6);
        pdExpenseFromFreee.getExpenseInfoByBaseDate(Date.today(), 6);
    }
}
