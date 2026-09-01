import Testing
@testable import RouteWarriorKit

struct GreetingTests {
    @Test func greetsByName() {
        #expect(Greeting.message(for: "Brian") == "Hello, Brian.")
    }

    @Test func trimsWhitespace() {
        #expect(Greeting.message(for: "  Brian \n") == "Hello, Brian.")
    }

    @Test func handlesEmptyName() {
        #expect(Greeting.message(for: "   ") == "Hello.")
    }
}
