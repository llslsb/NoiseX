// harmonyos-pack 版本号钩子模板（开发指南 §5.3「唯一官方姿势」）。
//
// 用法：把本文件内容合并进你工程根目录的 hvigorfile.ts（若工程已有自定义 hvigorfile，
// 只把 hvigor.getRootNode().afterNodeEvaluate(...) 这一段贴进去）。
//
// 机制（官方「定制构建 - 动态修改编译配置」示例）：
//   打包平台（hpk）通过环境变量 HPK_VERSION_CODE / HPK_VERSION_NAME 传入版本号，
//   本钩子在构建期改写本次构建的内存值——不写回 app.json5 文件，你的工作树保持干净。
//   不设置这两个变量时零影响：本地 DevEco 开发与 IDE 打包完全不受干扰，
//   版本号仍以 AppScope/app.json5 的静态值为准。
//
// 出处：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-config-ohos-sample
import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';

hvigor.getRootNode().afterNodeEvaluate((rootNode) => {
  const code = process.env.HPK_VERSION_CODE;
  const name = process.env.HPK_VERSION_NAME;
  if (!code && !name) {
    return; // 不设变量 = 零影响（本地 IDE 开发不受干扰）
  }
  const appContext = rootNode.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
  const appJsonOpt = appContext.getAppJsonOpt();
  if (code) {
    appJsonOpt['app']['versionCode'] = Number(code);
  }
  if (name) {
    appJsonOpt['app']['versionName'] = name;
  }
  appContext.setAppJsonOpt(appJsonOpt); // 只改本次构建的内存值，不写回 app.json5 文件
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
