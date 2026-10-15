import Foundation
import RealityKit
@main struct Inspect {
 @MainActor static func main() async throws {
  let root = try await Entity(contentsOf: URL(fileURLWithPath:CommandLine.arguments[1]))
  for (name,offset) in TidalScenePlacement.debrisOffsets {
   let e=root.findEntity(named:name)!
   e.setPosition(e.position(relativeTo:root)+offset,relativeTo:root)
  }
  var rows:[[String:Any]]=[]
  func vector(_ v:SIMD3<Float>)->[Float]{[v.x,v.y,v.z]}
  func visit(_ e:Entity,_ path:String) {
   let path=path+"/"+e.name
   if e.components[ModelComponent.self] != nil {
    let b=e.visualBounds(relativeTo:root)
    let content=e.components[ModelComponent.self]!.mesh.contents
    var points:[[Float]]=[]
    var triangles:[[UInt32]]=[]
    for instance in content.instances {
     guard let model=content.models.first(where:{$0.id==instance.model}) else {continue}
     for part in model.parts {
      let start=UInt32(points.count)
      for point in part.positions {
       let v=instance.transform * SIMD4<Float>(point,1)
       points.append(vector(e.convert(position:SIMD3<Float>(v.x,v.y,v.z),to:root)))
      }
      let indices=part.triangleIndices?.elements ?? []
      for i in stride(from:0,to:indices.count,by:3) {triangles.append([indices[i]+start,indices[i+1]+start,indices[i+2]+start])}
     }
    }
    rows.append(["path":path,"name":e.name,"parent":e.parent?.name ?? "", "min":vector(b.min),"max":vector(b.max),"center":vector(b.center), "vertices":points,"triangles":triangles])
   }
   for c in e.children {visit(c,path)}
  }
  visit(root,"")
  try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
 }
}
