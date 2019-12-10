"""
Created on Thu Sep 6 15:26:30 2018

@author: ytan
""" 
import os
from enum import Enum 
import tensorflow as tf 
from tensorflow.python.platform import gfile
from google.protobuf import text_format as pbtf  

from tensorflow.python.tools import optimize_for_inference_lib
from tensorflow.python.tools import freeze_graph
#from tensorflow.python.tools import import_pb_to_tensorboard as pb2TB  
import sys
import warnings
import argparse
from  tensorflow.python.framework import tensor_util 

INPUTNODE_TAG='_SensAI_BeginNode'
OUTPUTNODE_TAG='_SensAI_EndNode'


warnings.filterwarnings("ignore")


#from tensorflow.tools.graph_transforms.summarize_graph_main import SummarizeGraph #Can print out possible input nodes

def find_output_nodes(gdef, currNode):
    outNodes = []
    # print('find_output_nodes currNode ', currNode)

    for node in gdef.node:
        # if(node.op=='Sub'):
        # print('Sub node name  input',node.name,node.input)
        if node.name == currNode.name:
            continue
        if (currNode.op == 'Split'):
            for text in node.input:
                # print(currNode.name,'  output : ',node.name, node.input)
                if currNode.name in text:  # As split can be as input  as split:2,split:1, split
                    outNodes.append(node)
                    print(('Split out', node.name))
                    break

        else:
            if currNode.name in node.input:
                # print(currNode.name,'  output : ',node.name, node.input)
                outNodes.append(node)
    return outNodes
class tfPBfileMode(Enum):
     Binary=0
     Text=1
 
def setNodeAttribute(node, tag ,shapeArray):
    if(shapeArray is not None):
        if(tag=='shapes'): # here we assume  always only get first shape in shape list
             if(len(shapeArray)==4):
                  node.attr[tag].list.shape.extend([tf.TensorShape(shapeArray).as_proto()] )
             elif( len(shapeArray)==3): 
                 node.attr[tag].list.shape[0].dim[0].size =1
                 node.attr[tag].list.shape[0].dim[0].size = shapeArray[0]
                 node.attr[tag].list.shape[0].dim[1].size = shapeArray[1]
                 node.attr[tag].list.shape[0].dim[2].size = shapeArray[2]
                 
        if(tag=='shape'): #TODO  Set shape is not working  
                         
             if(len(shapeArray)==4):
                  node.attr[tag].shape.CopyFrom(tf.TensorShape(shapeArray).as_proto())    
             elif( len(shapeArray)==3): 
                 shapeArray4= [None] *4
                 
                 shapeArray4[0] = 1 
                 shapeArray4[1] = shapeArray[0]
                 shapeArray4[2] = shapeArray[1]
                 shapeArray4[3] = shapeArray[2]
                 node.attr[tag].shape.CopyFrom(tf.TensorShape(shapeArray4).as_proto())     
             #audio_model_wavInput Or other 2D input case. Normallay shape[1] is the the len of audio data len  but raw data  shape[0] is data lenth , so switch here  
             elif( len(shapeArray)==2): 
                 shapeArray2= [None] *2
                 
                 shapeArray2[0] = shapeArray[1]
                 shapeArray2[1] = shapeArray[0]
                 
                 node.attr[tag].shape.CopyFrom(tf.TensorShape(shapeArray2).as_proto())          
       

def setNodeConstValue(gdef,node,  value):
      output_node = tf.NodeDef() 
      output_node.name = node.name
      output_node.op = node.op
      dtype = node.attr["dtype"].type 
      output_node.attr["dtype"].type = dtype
      output_node.attr["value"].CopyFrom(tf.AttrValue(
      tensor=tf.contrib.util.make_tensor_proto(value, dtype=dtype )))   
      node.CopyFrom(output_node)
      return node

             
def getInputShapeForTF(node, tag ,forceNumTobe1=True):
    shapeArray= [None] *4
    if(tag=='shapes'): #TODO here we assume and always only get first shape in shape list
         if(len(node.attr[tag].list.shape)>0):
             if(len( node.attr[tag].list.shape[0].dim)==4): 
                  
                 for i in range(len(node.attr[tag].list.shape[0].dim)):
                     shapeArray[i] = node.attr[tag].list.shape[0].dim[i].size
            
             elif( len(node.attr[tag].list.shape[0].dim)==3):
                  
                 shapeArray[0] = 1 
                 shapeArray[1] = node.attr[tag].list.shape[0].dim[0].size
                 shapeArray[2] = node.attr[tag].list.shape[0].dim[1].size
                 shapeArray[3] = node.attr[tag].list.shape[0].dim[2].size
             
    if(tag=='shape'):  
         
         if(len( node.attr[tag].shape.dim)==4): 
              
             for i in range(len(node.attr[tag].shape.dim)):
                 shapeArray[i] = node.attr[tag].shape.dim[i].size
        
         elif( len(node.attr[tag].shape.dim)==3):
              
             shapeArray[0] = 1 
             shapeArray[1] = node.attr[tag].shape.dim[0].size
             shapeArray[2] = node.attr[tag].shape.dim[1].size
             shapeArray[3] = node.attr[tag].shape.dim[2].size
    
    if(tag=='output_shapes' or tag=='_output_shapes'):  
          if(len(node.attr[tag].list.shape)>0):
             if(len( node.attr[tag].list.shape[0].dim)==4): 
                  
                 for i in range(len(node.attr[tag].list.shape[0].dim)):
                     shapeArray[i] = node.attr[tag].list.shape[0].dim[i].size
            
             elif( len(node.attr[tag].list.shape[0].dim)==3):
                  
                 shapeArray[0] = 1 
                 shapeArray[1] = node.attr[tag].list.shape[0].dim[0].size
                 shapeArray[2] = node.attr[tag].list.shape[0].dim[1].size
                 shapeArray[3] = node.attr[tag].list.shape[0].dim[2].size
    
    if(forceNumTobe1 and shapeArray[0] is not None):
        shapeArray[0]=1 
                   
    return shapeArray
             

def getShapeArrays(node): 
    inputShape= [None] *4 
    inputShape = getInputShapeForTF(node,'shape')  
    print('inputShape shape',inputShape)
    if ( inputShape[0] is None):
        inputShape = getInputShapeForTF(node,'shapes')
        print('inputShape shapes',inputShape)
    if (inputShape[0] is not None): 
        return inputShape
    else:
        inputShape = getInputShapeForTF(node,'output_shapes')
        print('output_shapes of input Node',inputShape)
        if(inputShape[0] is None) :
            inputShape = getInputShapeForTF(node,'_output_shapes')
            if(inputShape[0] is None) :
                msg=' **TensorFlow**: can not locate input shape information at: ' +node.name
                print(msg)
            else:
                return inputShape
        else:
            return inputShape
       
        #raise Exception(msg) 

        
     
def createTensorboard(modelFullPath,tensorboardPath,runLocalimport_pb_to_tensorboard=True):  
      if not os.path.exists(tensorboardPath):
          os.makedirs(tensorboardPath)
      print('tensorboardPath:',tensorboardPath)
      map( os.unlink, (os.path.join( tensorboardPath,f) for f in os.listdir(tensorboardPath)) )
      pb2TB.import_to_tensorboard(modelFullPath,tensorboardPath)
     
def latestckpt(name):
  return int(name.split(".")[-2].split("-")[-1])

def parseCkptFolder(fullPathOfFolder,shapeInforNodeName,inputNodeName, outputNodeName):
    
    if(os.path.isfile(fullPathOfFolder)==False ):
        raise ValueError('Can not find : %s '%fullPathOfFolder)
         
    
    filename_w_ext = os.path.basename(fullPathOfFolder)
    modelName, file_extension = os.path.splitext(filename_w_ext)
    folderDir=os.path.dirname(fullPathOfFolder)+'/'
    
    files = os.listdir(folderDir)
    meta_files = [s for s in files if s.endswith('.meta')]
    meta_files = sorted(meta_files, key = latestckpt)
     
    graph_def = tf.GraphDef() 
    
    if len(meta_files)<1: #Only frozen model 
        raise ValueError('There should be at lease one meta file in the model directory (%s)'%folderDir)
     
    elif len(meta_files)>=1: 
        ckptFile = os.path.basename(meta_files[-1]) #The last check point is converted to pb
        print("using checkpoint :"+meta_files[-1])
        ckptWith1ndExtension, ckpt_metansion = os.path.splitext(ckptFile)
        ckptWith2ndExtension, ckptextension = os.path.splitext(ckptWith1ndExtension)
        
        if(file_extension=='.pbtxt'):
            with tf.gfile.FastGFile(fullPathOfFolder, 'r') as f:
                graph_str = f.read()
                pbtf.Parse(graph_str, graph_def)  
                ckptPBMode=tfPBfileMode.Text 
        else:
            with tf.gfile.FastGFile(fullPathOfFolder, 'rb') as f:
                graph_def.ParseFromString(f.read()) 
                ckptPBMode=tfPBfileMode.Binary 
        
     
    inputShapeArray=[] 
    graph_nodes=[n for n in graph_def.node]
    for node in graph_nodes: 
        if shapeInforNodeName == node.name: 
           inputShapeArray=getShapeArrays(node)  
           break
    return [ckptextension,ckptPBMode, folderDir,inputShapeArray,ckptWith2ndExtension] 
           
  

def settingsConf(modelInfors ): 
    checkpointExt=modelInfors[0]   
    pbFileType=modelInfors[1]
    checkpointPath= modelInfors[2] 
    folderPath=checkpointPath
    shapeArray= modelInfors[3] 
    ckptModelName=modelInfors[4] 
    if(pbFileType==tfPBfileMode.Binary):
        msuffix='.pb'   
        readMode='rb'
        binaryPB=True
    elif(pbFileType==tfPBfileMode.Text):
        binaryPB=False
        msuffix='.pbtxt' 
        readMode='r'  
    
    return msuffix,binaryPB,readMode,folderPath,checkpointExt,checkpointPath,shapeArray,ckptModelName

def loadGraph(filePath,binaryPB):
    graph_def = tf.GraphDef()
    if(binaryPB):
        with gfile.FastGFile(filePath,'rb') as f:
            graph_def.ParseFromString(f.read())
             
    else:
        with gfile.FastGFile(filePath,'r') as f:
            graph_str = f.read()
            pbtf.Parse(graph_str, graph_def)   
           
            
     # Then, we import the graph_def into a new Graph and returns it 
    with tf.Graph().as_default() as graph:
        # The name var will prefix every op/nodes in your graph
        # Since we load everything in a new graph, this is not needed
        tf.import_graph_def(graph_def, name="")         
    return graph,graph_def




   
def convert(file_path,inputNodeName, outputNodeName,msuffix,binaryPB,readMode,folderPath,checkpointExt,checkpointPath,modelName,shapeArray,modifyshapeAttribue ,fixBatchNormal=True) :
    tf.reset_default_graph()   
    os.environ['CUDA_VISIBLE_DEVICES']=''
    config = tf.ConfigProto(
            allow_soft_placement = True,
            device_count={"GPU": 0, "CPU": 1}
            
    )
    runIncommdLine=False
    if(os.path.isfile(file_path)):
        g_in,graph_def =  loadGraph(file_path,binaryPB)  
    else:
        raise ValueError('Can not find : %s '%folderDir)
    
    fixTrainingBNAndDropout=False
    if(fixTrainingBNAndDropout):
        fcQuantWeightRemoved=False
        import tensorflow.contrib.graph_editor   as ge 
        maxModuleNumber=6
        for i in range(1,maxModuleNumber+1): #if fire 6 is last fire layer set to 7
            blockName='fire'+str(i)
            if(i==1):
                bnNames=['/bn'] # mobile net First layer  Quant model all 7 fires are '/bn'
            else:
                bnNames=['/bn']  # mobile net ['/dw_bn','/1x1_bn']  Squeeze Net  ['/bn']
            useConnectMethod=False
            for bnName in bnNames:
                if(useConnectMethod):
                    nodeName=blockName+bnName+'/moments/Squeeze_1'
                    oldInputName=blockName+bnName+'/moments/variance'
                    newInputName=blockName+bnName+'/moving_variance' 
                    node= g_in.get_operation_by_name(nodeName)                  
                    oldInputNode=g_in.get_operation_by_name(oldInputName)  
                    newInputNode=g_in.get_operation_by_name(newInputName) 
                    placeHolderNew= tf.identity(newInputNode.outputs[0])
                    expDim=tf.expand_dims(tf.expand_dims(tf.expand_dims(placeHolderNew,0),0),0)                
                    ge.detach (ge.sgv(oldInputNode))
                    ge.connect(ge.sgv(expDim),ge.sgv(node) )
                    nodeName=blockName+bnName+'/moments/Squeeze'
                    oldInputName=blockName+bnName+'/moments/mean'
                    newInputName=blockName+bnName+'/moving_mean' 
                    node= g_in.get_operation_by_name(nodeName)  
                    print('%s before edit new node  node.node_def  .inputs[0]'%blockName, node.node_def  , node.inputs[0])            
                    oldInputNode=g_in.get_operation_by_name(oldInputName)  
                    newInputNode=g_in.get_operation_by_name(newInputName) 
                    placeHolderNew= tf.identity(newInputNode.outputs[0])
                    expDim=tf.expand_dims(tf.expand_dims(tf.expand_dims(placeHolderNew,0),0),0) 
                    ge.detach (ge.sgv(oldInputNode))
                    ge.connect(ge.sgv(expDim),ge.sgv(node) )  
                    print('%s after edit new node  node.node_def  .inputs[0]'%blockName, node.node_def  , node.inputs[0])
                else:
                    
                    oldInputName=blockName+bnName+'/moments/Squeeze_1'
                    newInputName=blockName+bnName+'/moving_variance'              
                    oldInputNode=g_in.get_operation_by_name(oldInputName)  
                    newInputNode=g_in.get_operation_by_name(newInputName) 
                    placeHolderNew= tf.identity(newInputNode.outputs[0])      
                    ge.swap_outputs(ge.sgv(placeHolderNew),ge.sgv(oldInputNode) )
                    oldInputName=blockName+bnName+'/moments/Squeeze'
                    newInputName=blockName+bnName+'/moving_mean'         
                    oldInputNode=g_in.get_operation_by_name(oldInputName)  
                    newInputNode=g_in.get_operation_by_name(newInputName) 
                    placeHolderNew= tf.identity(newInputNode.outputs[0])  
                    ge.swap_outputs(ge.sgv(placeHolderNew),ge.sgv(oldInputNode) )  
            removeWeightQuantize=False
            if(removeWeightQuantize):
                oldInputName=blockName+'/conv3x3/add'
                newInputName=blockName+'/conv3x3/kernels'  
                #print('%s before edit new node  node.node_def  .inputs[0]'%blockName, node.node_def  , node.inputs[0])
                oldInputNode=g_in.get_operation_by_name(oldInputName)  
                newInputNode=g_in.get_operation_by_name(newInputName) 
                placeHolderNew= tf.identity(newInputNode.outputs[0])
#                expDim=tf.expand_dims(tf.expand_dims(tf.expand_dims(placeHolderNew,0),0),0) 
#                ge.detach (ge.sgv(oldInputNode))
                ge.swap_outputs(ge.sgv(placeHolderNew),ge.sgv(oldInputNode) ) #reroute_outputs get same results  
                #Remove FC layer
                if(fcQuantWeightRemoved==False): 
                    oldInputName='logit/add'
                    newInputName='logit/weights'  
                    #print('%s before edit new node  node.node_def  .inputs[0]'%blockName, node.node_def  , node.inputs[0])
                    
                    oldInputNode=g_in.get_operation_by_name(oldInputName)  
                    newInputNode=g_in.get_operation_by_name(newInputName) 
                    placeHolderNew= tf.identity(newInputNode.outputs[0])
    #                expDim=tf.expand_dims(tf.expand_dims(tf.expand_dims(placeHolderNew,0),0),0) 
    #                ge.detach (ge.sgv(oldInputNode))
                    ge.swap_outputs(ge.sgv(placeHolderNew),ge.sgv(oldInputNode) ) #reroute_outputs get same results  
                    fcQuantWeightRemoved=True
                
                
            
           
            with tf.Session(config=config,graph =g_in) as sess: 
                            graph_def=sess.graph_def
                            
                            for node in graph_def.node:
                                if 'dropout/mul' in node.name:
                                    deleteDropOut=True              
                                    if(deleteDropOut): 
                                        oldInputName= 'dropout/mul'
                                        newInputName= 'fire6/pool/MaxPool'  
                                        oldInputNode=g_in.get_operation_by_name(oldInputName)  
                                        newInputNode=g_in.get_operation_by_name(newInputName) 
                                        placeHolderNew= tf.identity(newInputNode.outputs[0]) 
                                        ge.swap_outputs(ge.sgv(placeHolderNew),ge.sgv(oldInputNode) ) #reroute_outputs get same results  
                            
                                    else:   
                                        for node in graph_def.node:
                                            if node.name == 'dropout/keep_prob':
                                                #node.attr['value'].tensor.float_val=tf.convert_to_tensor (1,dtype=tf.float32)
                                                #node.attr['value'].tensor.float_val=1
                                                node.attr['value'].tensor.CopyFrom(tensor_util.make_tensor_proto(1.0,dtype=tf.float32) )
                                                #node.attr['value'].value =1.0
    # fix batch normal node nodes  https://github.com/tensorflow/tensorflow/issues/3628
    if(fixBatchNormal): 
         
        for node in graph_def.node:
          if node.op == 'RefSwitch':
            node.op = 'Switch'
            for index in  range(len(node.input)):
              if 'moving_' in node.input[index]:
                node.input[index] = node.input[index] + '/read'
          elif node.op == 'AssignSub':
            node.op = 'Sub'
            if 'use_locking' in node.attr: del node.attr['use_locking']
          elif node.op == 'AssignAdd':
            node.op = 'Add'
            if 'use_locking' in node.attr: del node.attr['use_locking']
          if('dilations')    in node.attr: del node.attr['dilations']  
          node.device=""
          
          
        #fixVariables not Working  
        fixVariables  =False 
        if (fixVariables and node.op == 'VariableV2' and ('batchnorm/var' in node.name or 'batchnorm/mean' in node.name)):
              outputNodes=find_output_nodes(graph_def,node) 
              for index in  range(len( outputNodes )):
                  if(outputNodes[index].op=='Assign'   ):
                        #node.output[index] = node.output[index] + '/read'
                        #outputNodes[index].op ='Identity'
                        outputNodes[index].name = outputNodes[index].name+ '/read'
                        print('Modified %s '%outputNodes[index].name) 
                       
                 
 
                 
                
   
                    
#################### Step 1 Training to inference simplification  , need checkpoint and  .pbtxt files from training   ######################################################      
               
                
    graphDef = optimize_for_inference_lib.optimize_for_inference(
                        graph_def,
                        [inputNodeName], # an array of the input node(s)
                        [outputNodeName] if type(outputNodeName)  is str  else [item for item in outputNodeName  ], # an array of output nodes
                        tf.float32.as_datatype_enum)
    if(modifyshapeAttribue):
        inputOpType='Placeholder'
        for n in  graphDef.node: 
            #print('node to modify',n.name)
            if( n.name==inputNodeName):
                print('node to modify',n)
                setNodeAttribute(n,'shape',shapeArray)
                if(n.op !=inputOpType):
                       print("--Node %s op   %s   set to op=%s" %( inputNodeName, n.op,inputOpType),shapeArray)
                       n.op=inputOpType
                print("--Name of the node - %s shape set to " %  n.name,shapeArray)
                print('node after modify',n)
     
    
    modifyClipValue=False
    if(modifyClipValue):
         for i in range(1,maxModuleNumber+1): 
                blockName='fire'+str(i)
                newClipValue=127
                
                clipVNodeName=blockName +'/conv3x3/Rint_1/x'
                #clipnode= g_in.get_operation_by_name(clipVNodeName)
                clipnode= find_node_by_name(graphDef,clipVNodeName)
                     
                print('clipnode to modify',clipnode)
                
                setNodeConstValue(graph_def,clipnode, newClipValue) 
                
                print("--Name of the node - %s shape set to %f" % ( clipnode.name, newClipValue))
                print('clipnode after modify',clipnode)
                
                modifyFCClip=True
                if( modifyFCClip and i==maxModuleNumber):
                    clipVNodeName='conv12/Rint_1/x'   
                    clipnodeFC= find_node_by_name(graphDef,clipVNodeName) 
                    #clipnodeFC= g_in.get_operation_by_name(clipVNodeName)
                    setNodeConstValue(graph_def,clipnodeFC, newClipValue)
                   
                    print('clipnode after modify',clipnodeFC)   
       
           
    if(runIncommdLine):
        copyfile(file_path,file_path+trainModelSuffix)  
    outputNameSuffix=  '%s_frozenforInference.pb'%checkpointExt
    inferenceSuffix='.Inference'
    tf.train.write_graph(graphDef,folderPath, checkpointPath+modelName+'.pb'+inferenceSuffix, as_text=False)  
    tf.train.write_graph(graphDef,folderPath, checkpointPath+modelName+'.pbtxt'+inferenceSuffix, as_text=True)
        
    
    
    
    pbfileoutput_path=checkpointPath+modelName+outputNameSuffix
    checkpointfile_path=checkpointPath+modelName+checkpointExt
          
    pbfile_path=checkpointPath+modelName+msuffix+inferenceSuffix 
####################   Step 2                    Frozen Inference mode                      ######################################################                     
    
    freeze_graph.freeze_graph(
                        input_graph=pbfile_path, 
                        input_saver='',
                        input_binary=binaryPB,
                        input_checkpoint=checkpointfile_path, # an array of the input node(s)
                        output_node_names=  outputNodeName  if type(outputNodeName)  is str  else  ",".join( outputNodeName),
                        restore_op_name="save/restore_all", #Unused.
                        filename_tensor_name="save/Const:0",# Unused.
                        output_graph=pbfileoutput_path, # an array of output nodes  
                        clear_devices=True,
                        initializer_nodes=''
                        )
####################   Step 3                    Save in tensor board                     ######################################################                                         
    saveTensorboardForVisualizatoin=False
    if(saveTensorboardForVisualizatoin):
        modelFullPath=checkpointPath+modelName+outputNameSuffix                   
        tensorboardPath=checkpointPath+ '\\tensorboard'
        #if not os.path.exists(tensorboardPath):
        #  os.mkdir(tensorboardPath)
        createTensorboard(modelFullPath,tensorboardPath) 


def parseParameters(dataPara,inputTag=INPUTNODE_TAG,outputTag=OUTPUTNODE_TAG):
    if(len(dataPara)>3):
        return
    elif(len(dataPara)<3): #Auto mode : provide only path and shape (shape is optional)
        print('Only path provided and expect graph have predefined input and output tag')
        g,gdef =  loadGraph(dataPara[0],False)  
        inputNodes={n.name:n.op for n in gdef.node if n.op in (   'FIFOQueueV2','QueueDequeueManyV2', 'Placeholder') and inputTag in n.name}
        outputNodes={n.name:n.op for n in gdef.node if n.op in (   'Conv2D','MatMul','Mean', 'AvgPool','MaxPool','Add' ,'BiasAdd') and outputTag in n.name}
       
        if(len(inputNodes)==1):
          inputName=list(inputNodes.keys())[0]
          dataPara.insert(1,inputName) 
          if(len(outputNodes)==1):
              outputName=list(outputNodes.keys())[0]
              dataPara.insert(2,outputName)  
              dataPara.insert(3,inputName)    
              
        if(len(dataPara)<3):
            print('Error: Can not find input output in graph or there are multiple input or multiple output.' )
            sys.exit()
        if(len(dataPara)==4  ):
            dataPara.insert(4,False) #Default Do not modify shape
        elif (len(dataPara)==5  and dataPara[4]==True) :
            print('Error: Set modify shape but does not specify shape array [n,h,w,c].' )
            sys.exit()
        print(inputNodes)
        print(outputNodes )
        

freezeWithoutPb=False
if(freezeWithoutPb): 
       
    paras=[
            ['Quant_Humancnt_UPlus','.ckpt-249999.meta','conv12/convolution'],
            ['ShuffleNet','.ckpt-1331064.meta','evaluation_ops/Mean_1'],
            ['MobileNet','.ckpt.meta','MobilenetV2/Logits/Conv2d_1c_1x1/biases'],  
            ['HumanGesture','.ckpt-41342.meta','logit/add'],
            ['humandet','.ckpt.meta','conv12/convolution']]
    dataIndex=0
    modelName=paras[dataIndex][0]  
    ckptPath=r'T:\Data\Model\\'+modelName+'\checkpoint\\'
    meta_path =ckptPath+ modelName+paras[dataIndex][1]    
    output_node_names =[paras[dataIndex][2] ] # ['logit/add']    # Output nodes
    
    tf.reset_default_graph() 
    
    #
    with tf.Session(config=tf.ConfigProto(allow_soft_placement=True, log_device_placement=True)) as sess:
         
        # Restore the graph
        #
        saver = tf.train.import_meta_graph(meta_path)
        # Load weights
        #Need checkpoint file as 
        #model_checkpoint_path: "T:\Yiyong\Data\Model\ShuffleNet\ckptNopbtxt\ShuffleNet.ckpt-1331064"
        #all_model_checkpoint_paths: "T:\Yiyong\Data\Model\ShuffleNet\ckptNopbtxt\ShuffleNet.ckpt-1331064"
        
        if(os.path.isfile(ckptPath+'checkpoint') ):
            saver.restore(sess,tf.train.latest_checkpoint(ckptPath))
        else:
            checkpointFileToLoad=meta_path.replace('.meta','')
            saver.restore(sess,checkpointFileToLoad)
        tf.train.write_graph(sess.graph_def,ckptPath, modelName+'WithoutCKPTPBTxt.pbtxt')
        # Freeze the graph\
        frozenGraphWithoutOpimization=False #Set true will create duplicate graph if write_graph is after it
        if(frozenGraphWithoutOpimization):
               frozen_graph_def = tf.graph_util.convert_variables_to_constants(
                   sess,
                   sess.graph_def,
                   output_node_names)
           
               # Save the frozen graph
               with open(ckptPath+   modelName+'WithoutCKPTPBTxtFrozen.pb', 'wb') as f:
                 f.write(frozen_graph_def.SerializeToString())
               with open(ckptPath+  modelName+'WithoutCKPTPBTxt.pb', 'wb') as f:
                 f.write(sess.graph_def.SerializeToString())
        
        
          
    sys.exit()         
        

def demoCKPT2PB(dataPara): 
    parseParameters(dataPara) 
    file_path=dataPara[0]    
    inputNodeName=dataPara[1]  
    outputNodeName =dataPara[2]
    if(len(dataPara)>3):
        shapeInforNodeName= dataPara[3] 
    else:
        shapeInforNodeName =dataPara[1]
    if(len(dataPara)>4):
        modifyInputShape= dataPara[4]  
    else:
        modifyInputShape=False  #Default Not to modify input shape
    
    msuffix,binaryPB,readMode,folderPath,checkpointExt,checkpointPath,shapeArray,modelName=settingsConf(parseCkptFolder(file_path,shapeInforNodeName,inputNodeName,outputNodeName)  )
    
   
    
    if(   len(dataPara)<6   ):   
        if(   shapeArray is None or len(shapeArray)<1 ):
            print('Error: Can not find shape information in graph and user does not provide input shape information' )
            sys.exit()
    else:        
        shapeArray=dataPara[5]  
    convert(file_path,inputNodeName, outputNodeName,msuffix,binaryPB,readMode,'',checkpointExt,checkpointPath,modelName,shapeArray,modifyInputShape)
    

def main():
  indexOfModel=0
  dataParas=[[r'./tinyvgg_conv.pbtxt','audio_input', 'fc4/BiasAdd','audio_input',True,[8320, 1]  ]]
  demoCKPT2PB(dataParas[indexOfModel])



if __name__ == '__main__':
  parser = argparse.ArgumentParser()
  os.environ['CUDA_VISIBLE_DEVICES'] = '-1'
  parser.add_argument("--ckpt_dir", type=str, required=True, default="", help="Checkpoint directory")
  args = parser.parse_args()
  os.chdir(os.path.abspath(args.ckpt_dir))
  main()
  
