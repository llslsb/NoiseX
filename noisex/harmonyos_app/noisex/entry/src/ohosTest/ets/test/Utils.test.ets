import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { Utils } from '../../../main/ets/common/Utils';

export default function utilsTest() {
  describe('UtilsTest', () => {
    beforeAll(() => {})
    beforeEach(() => {})
    afterEach(() => {})
    afterAll(() => {})

    it('generateId_shouldReturnNonEmptyString', 0, () => {
      const id: string = Utils.generateId();
      expect(id.length > 0).assertTrue();
    })

    it('generateId_shouldContainHyphen', 0, () => {
      const id: string = Utils.generateId();
      expect(id.indexOf('-') !== -1).assertTrue();
    })

    it('generateId_shouldStartWithTimestamp', 0, () => {
      const before: number = Date.now();
      const id: string = Utils.generateId();
      const after: number = Date.now();
      const parts: string[] = id.split('-');
      expect(parts.length).assertEqual(2);
      const ts: number = parseInt(parts[0], 10);
      expect(ts >= before && ts <= after).assertTrue();
    })

    it('generateId_shouldHaveNumericSuffix', 0, () => {
      const id: string = Utils.generateId();
      const parts: string[] = id.split('-');
      const suffix: number = parseInt(parts[1], 10);
      expect(suffix >= 0 && suffix < 10000).assertTrue();
    })

    it('generateId_shouldBeUnique', 0, () => {
      const id1: string = Utils.generateId();
      const id2: string = Utils.generateId();
      expect(id1 === id2).assertFalse();
    })
  })
}
