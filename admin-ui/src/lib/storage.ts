import type { BalanceResponse } from '@/types/api'

const API_KEY_STORAGE_KEY = 'adminApiKey'
const BALANCE_CACHE_KEY = 'credentialBalanceCache'

export const storage = {
  getApiKey: () => localStorage.getItem(API_KEY_STORAGE_KEY),
  setApiKey: (key: string) => localStorage.setItem(API_KEY_STORAGE_KEY, key),
  removeApiKey: () => localStorage.removeItem(API_KEY_STORAGE_KEY),

  // 获取余额缓存数据
  getBalanceCache: (): Map<number, BalanceResponse> => {
    try {
      const cached = localStorage.getItem(BALANCE_CACHE_KEY)
      if (!cached) {
        return new Map()
      }
      const parsed = JSON.parse(cached) as Record<string, BalanceResponse>
      // 将对象转换为 Map，键转换为数字类型
      return new Map(Object.entries(parsed).map(([id, balance]) => [Number(id), balance]))
    } catch (error) {
      console.error('读取余额缓存失败:', error)
      return new Map()
    }
  },

  // 保存余额缓存数据
  setBalanceCache: (cache: Map<number, BalanceResponse>): void => {
    try {
      // 将 Map 转换为普通对象以便 JSON 序列化
      const obj = Object.fromEntries(cache.entries())
      localStorage.setItem(BALANCE_CACHE_KEY, JSON.stringify(obj))
    } catch (error) {
      console.error('保存余额缓存失败:', error)
      // localStorage 满或被禁用时静默失败，不影响功能
    }
  },
}
