#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>
CAP_PLUGIN(SurvivalMeshPlugin, "SurvivalMesh",
  CAP_PLUGIN_METHOD(start, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(stop, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(send, CAPPluginReturnPromise);
  CAP_PLUGIN_METHOD(getPeers, CAPPluginReturnPromise);
)