global class pdExpenseFromFreeeJob implements Schedulable {
    global void execute(SchedulableContext ctx) {
        pdExpenseFromFreee.getExpenseInfo(null, 4);
    }
}
