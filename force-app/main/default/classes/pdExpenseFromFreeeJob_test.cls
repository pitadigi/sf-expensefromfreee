@isTest(SeeAllData=true)
class pdExpenseFromFreeeJob_test {
    static String CRON_EXP = '0 0 0 3 9 ? 2022';
    
    @isTest
    static void doTest() {
        Test.setMock(HttpCalloutMock.class, new pdExpenseFromFreeeCalloutMock());
        Test.startTest();

        try {
            String jobId = System.schedule('pdExpenseFromFreeeJob_test',
                CRON_EXP,
                new pdExpenseFromFreeeJob());
        }
        catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
        }
    
        Test.stopTest();
    }
}
