-- Globals TestEZ injects into *.spec modules. Loaded only when type-checking tests/.
declare function describe(phrase: string, callback: () -> ()): ()
declare function it(phrase: string, callback: () -> ()): ()
declare function itSKIP(phrase: string, callback: () -> ()): ()
declare function itFOCUS(phrase: string, callback: () -> ()): ()
declare function beforeAll(callback: () -> ()): ()
declare function afterAll(callback: () -> ()): ()
declare function beforeEach(callback: () -> ()): ()
declare function afterEach(callback: () -> ()): ()
-- TestEZ's chained matcher API (expect(x).to.equal(y)) is untyped upstream.
declare function expect(value: any): any
