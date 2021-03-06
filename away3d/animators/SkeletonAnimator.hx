/**
 * Provides an interface for assigning skeleton-based animation data sets to mesh-based entity objects
 * and controlling the various available states of animation through an interative playhead that can be
 * automatically updated or manually triggered.
 */
package away3d.animators;

import away3d.animators.data.SkeletonJoint;
import away3d.core.math.Quaternion;
import openfl.geom.Vector3D;
import away3d.animators.data.JointPose;
import away3d.materials.passes.MaterialPassBase;
import openfl.display3D.Context3DProgramType;
import away3d.core.managers.Stage3DProxy;
import away3d.core.base.IRenderable;
import away3d.cameras.Camera3D;
import away3d.core.base.SubMesh;
import away3d.core.base.SkinnedSubGeometry;
import away3d.events.AnimationStateEvent;
import openfl.errors.Error;
import away3d.animators.transitions.IAnimationTransition;
import away3d.animators.states.ISkeletonAnimationState;
import haxe.ds.ObjectMap;

import away3d.animators.data.SkeletonPose;
import away3d.animators.data.Skeleton;

import away3d.core.base.CompactSubGeometry;

import openfl.Vector;

class SkeletonAnimator extends AnimatorBase implements IAnimator {
    public var globalMatrices(get_globalMatrices, never):Vector<Float>;
    public var globalPose(get_globalPose, never):SkeletonPose;
    public var skeleton(get_skeleton, never):Skeleton;
    public var forceCPU(get_forceCPU, never):Bool;
    public var useCondensedIndices(get_useCondensedIndices, set_useCondensedIndices):Bool;

    private var _globalMatrices:Vector<Float>;
    private var _globalPose:SkeletonPose;
    private var _globalPropertiesDirty:Bool;
    private var _numJoints:Int;
    private var _skeletonAnimationStates:ObjectMap<SkinnedSubGeometry, SubGeomAnimationState>;
    private var _condensedMatrices:Vector<Float>;
    private var _skeleton:Skeleton;
    private var _forceCPU:Bool;
    private var _useCondensedIndices:Bool;
    private var _jointsPerVertex:Int;
    private var _activeSkeletonState:ISkeletonAnimationState;

    /**
	 * returns the calculated global matrices of the current skeleton pose.
	 *
	 * @see #globalPose
	 */
    public function get_globalMatrices():Vector<Float> {
        if (_globalPropertiesDirty) updateGlobalProperties();
        return _globalMatrices;
    }

    /**
	 * returns the current skeleton pose output from the animator.
	 *
	 * @see away3d.animators.data.SkeletonPose
	 */
    public function get_globalPose():SkeletonPose {
        if (_globalPropertiesDirty) updateGlobalProperties();
        return _globalPose;
    }

    /**
	 * Returns the skeleton object in use by the animator - this defines the number and heirarchy of joints used by the
	 * skinned geoemtry to which skeleon animator is applied.
	 */
    public function get_skeleton():Skeleton {
        return _skeleton;
    }

    /**
	 * Indicates whether the skeleton animator is disabled by default for GPU rendering, something that allows the animator to perform calculation on the GPU.
	 * Defaults to false.
	 */
    public function get_forceCPU():Bool {
        return _forceCPU;
    }

    /**
	 * Offers the option of enabling GPU accelerated animation on skeletons larger than 32 joints
	 * by condensing the number of joint index values required per mesh. Only applicable to
	 * skeleton animations that utilise more than one mesh object. Defaults to false.
	 */
    public function get_useCondensedIndices():Bool {
        return _useCondensedIndices;
    }

    public function set_useCondensedIndices(value:Bool):Bool {
        _useCondensedIndices = value;
        return value;
    }

    /**
	 * Creates a new <code>SkeletonAnimator</code> object.
	 *
	 * @param skeletonAnimationSet The animation data set containing the skeleton animations used by the animator.
	 * @param skeleton The skeleton object used for calculating the resulting global matrices for transforming skinned mesh data.
	 * @param forceCPU Optional value that only allows the animator to perform calculation on the CPU. Defaults to false.
	 */
    public function new(animationSet:SkeletonAnimationSet, skeleton:Skeleton, forceCPU:Bool = false) {
        _globalPose = new SkeletonPose();
        _skeletonAnimationStates = new ObjectMap<SkinnedSubGeometry, SubGeomAnimationState>();
        super(animationSet);
        
        _skeleton = skeleton;
        _forceCPU = forceCPU;
        _jointsPerVertex = animationSet.jointsPerVertex;
        _numJoints = _skeleton.numJoints;
        _globalMatrices = new Vector<Float>();
        var j:Int = 0;
        var i:Int = 0;
        while (i < _numJoints) {
            _globalMatrices[j++] = 1;
            _globalMatrices[j++] = 0;
            _globalMatrices[j++] = 0;
            _globalMatrices[j++] = 0;
            _globalMatrices[j++] = 0;
            _globalMatrices[j++] = 1;
            _globalMatrices[j++] = 0;
            _globalMatrices[j++] = 0;
            _globalMatrices[j++] = 0;
            _globalMatrices[j++] = 0;
            _globalMatrices[j++] = 1;
            _globalMatrices[j++] = 0;
            ++i;
        }
    }

    /**
	 * @inheritDoc
	 */
    public function clone():IAnimator {
        /* The cast to SkeletonAnimationSet should never fail, as _animationSet can only be set
		 through the constructor, which will only accept a SkeletonAnimationSet. */
        return new SkeletonAnimator( cast(_animationSet, SkeletonAnimationSet), _skeleton, _forceCPU);
    }

    /**
	 * Plays an animation state registered with the given name in the animation data set.
	 *
	 * @param name The data set name of the animation state to be played.
	 * @param transition An optional transition object that determines how the animator will transition from the currently active animation state.
	 * @param offset An option offset time (in milliseconds) that resets the state's internal clock to the absolute time of the animator plus the offset value. Required for non-looping animation states.
	 */
    public function play(name:String, ?transition:IAnimationTransition = null, ?offset:Int = null):Void {
        if (_activeAnimationName == name) return;
        
        _activeAnimationName = name;
        if (!_animationSet.hasAnimation(name)) 
            throw new Error("Animation root node " + name + " not found!");
        
        if (transition != null && _activeNode != null) {
            //setup the transition
            _activeNode = transition.getAnimationNode(this, _activeNode, _animationSet.getAnimation(name), _absoluteTime);
            _activeNode.addEventListener(AnimationStateEvent.TRANSITION_COMPLETE, onTransitionComplete);
        } else 
            _activeNode = _animationSet.getAnimation(name);
        
        _activeState = getAnimationState(_activeNode);
        if (updatePosition) {
            //update straight away to reset position deltas
            _activeState.update(_absoluteTime);
            _activeState.positionDelta;
        }
        
        _activeSkeletonState = cast(_activeState, ISkeletonAnimationState) ;
        start();
        
        //apply a time offset if specified
        if (offset!=null && !Math.isNaN(offset)) reset(name, Std.int(offset));
    }

    /**
	 * @inheritDoc
	 */
    public function setRenderState(stage3DProxy:Stage3DProxy, renderable:IRenderable, vertexConstantOffset:Int, vertexStreamOffset:Int, camera:Camera3D):Void {
        // do on request of globalProperties
        if (_globalPropertiesDirty) 
            updateGlobalProperties();
        
        var skinnedGeom:SkinnedSubGeometry = cast((cast((renderable), SubMesh).subGeometry), SkinnedSubGeometry);
        
        // using condensed data
        var numCondensedJoints:Int = skinnedGeom.numCondensedJoints;
        if (_useCondensedIndices) {
            if (skinnedGeom.numCondensedJoints == 0) {
                skinnedGeom.condenseIndexData();
                numCondensedJoints = skinnedGeom.numCondensedJoints;
            }
            updateCondensedMatrices(skinnedGeom.condensedIndexLookUp, numCondensedJoints);
            stage3DProxy._context3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, vertexConstantOffset, _condensedMatrices, numCondensedJoints * 3);
        } else {
            if (_animationSet.usesCPU) {
                if (!_skeletonAnimationStates.exists(skinnedGeom))
                    _skeletonAnimationStates.set(skinnedGeom, new SubGeomAnimationState(skinnedGeom));
                var subGeomAnimState:SubGeomAnimationState = _skeletonAnimationStates.get(skinnedGeom);
                if (subGeomAnimState.dirty) {
                    morphGeometry(subGeomAnimState, skinnedGeom);
                    subGeomAnimState.dirty = false;
                }
                skinnedGeom.updateAnimatedData(subGeomAnimState.animatedVertexData);
                return;
            }
            stage3DProxy._context3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, vertexConstantOffset, _globalMatrices, _numJoints * 3);
        }

        skinnedGeom.activateJointIndexBuffer(vertexStreamOffset, stage3DProxy);
        skinnedGeom.activateJointWeightsBuffer(vertexStreamOffset + 1, stage3DProxy);
    }

    /**
	 * @inheritDoc
	 */
    public function testGPUCompatibility(pass:MaterialPassBase):Void {
        if (!_useCondensedIndices && (_forceCPU || _jointsPerVertex > 4 || pass.numUsedVertexConstants + _numJoints * 3 > 128)) _animationSet.cancelGPUCompatibility();
    }

    /**
	 * Applies the calculated time delta to the active animation state node or state transition object.
	 */
    override private function updateDeltaTime(dt:Int):Void {
        super.updateDeltaTime(dt);
        //invalidate pose matrices
        _globalPropertiesDirty = true;
        var iterator = _skeletonAnimationStates.iterator();
        for (state in iterator)
            state.dirty = true;
    }

    private function updateCondensedMatrices(condensedIndexLookUp:Vector<UInt>, numJoints:Int):Void {
        var i:Int = 0;
        var j:Int = 0;
        var len:Int;
        var srcIndex:Int;
        _condensedMatrices = new Vector<Float>();
        do {
            srcIndex = condensedIndexLookUp[i * 3] * 4;
            len = srcIndex + 12;
            // copy into condensed
            while (srcIndex < len)_condensedMatrices[j++] = _globalMatrices[srcIndex++];
        } while ((++i < numJoints));
    }

    private function updateGlobalProperties():Void {
        _globalPropertiesDirty = false;
        
        //get global pose
        localToGlobalPose(_activeSkeletonState.getSkeletonPose(_skeleton), _globalPose, _skeleton);

        // convert pose to matrix
        var mtxOffset:Int = 0;
        var globalPoses:Vector<JointPose> = _globalPose.jointPoses;
        var raw:Vector<Float>;
        var ox:Float;
        var oy:Float;
        var oz:Float;
        var ow:Float;
        var xy2:Float;
        var xz2:Float;
        var xw2:Float;
        var yz2:Float;
        var yw2:Float;
        var zw2:Float;
        var n11:Float;
        var n12:Float;
        var n13:Float;
        var n21:Float;
        var n22:Float;
        var n23:Float;
        var n31:Float;
        var n32:Float;
        var n33:Float;
        var m11:Float;
        var m12:Float;
        var m13:Float;
        var m14:Float;
        var m21:Float;
        var m22:Float;
        var m23:Float;
        var m24:Float;
        var m31:Float;
        var m32:Float;
        var m33:Float;
        var m34:Float;
        var joints:Vector<SkeletonJoint> = _skeleton.joints;
        var pose:JointPose;
        var quat:Quaternion;
        var vec:Vector3D;
        var t:Float;
        var i:Int = 0;
        while (i < _numJoints) {
            pose = globalPoses[i];
            quat = pose.orientation;
            vec = pose.translation;
            ox = quat.x;
            oy = quat.y;
            oz = quat.z;
            ow = quat.w;
            xy2 = (t = 2.0 * ox) * oy;
            xz2 = t * oz;
            xw2 = t * ow;
            yz2 = (t = 2.0 * oy) * oz;
            yw2 = t * ow;
            zw2 = 2.0 * oz * ow;
            yz2 = 2.0 * oy * oz;
            yw2 = 2.0 * oy * ow;
            zw2 = 2.0 * oz * ow;
            ox *= ox;
            oy *= oy;
            oz *= oz;
            ow *= ow;
            n11 = (t = ox - oy) - oz + ow;
            n12 = xy2 - zw2;
            n13 = xz2 + yw2;
            n21 = xy2 + zw2;
            n22 = -t - oz + ow;
            n23 = yz2 - xw2;
            n31 = xz2 - yw2;
            n32 = yz2 + xw2;
            n33 = -ox - oy + oz + ow;
            // prepend inverse bind pose
            raw = joints[i].inverseBindPose;
            m11 = raw[0];
            m12 = raw[4];
            m13 = raw[8];
            m14 = raw[12];
            m21 = raw[1];
            m22 = raw[5];
            m23 = raw[9];
            m24 = raw[13];
            m31 = raw[2];
            m32 = raw[6];
            m33 = raw[10];
            m34 = raw[14];
            
            _globalMatrices[(mtxOffset)] = n11 * m11 + n12 * m21 + n13 * m31;
            _globalMatrices[(mtxOffset + 1)] = n11 * m12 + n12 * m22 + n13 * m32;
            _globalMatrices[(mtxOffset + 2)] = n11 * m13 + n12 * m23 + n13 * m33;
            _globalMatrices[(mtxOffset + 3)] = n11 * m14 + n12 * m24 + n13 * m34 + vec.x;
            _globalMatrices[(mtxOffset + 4)] = n21 * m11 + n22 * m21 + n23 * m31;
            _globalMatrices[(mtxOffset + 5)] = n21 * m12 + n22 * m22 + n23 * m32;
            _globalMatrices[(mtxOffset + 6)] = n21 * m13 + n22 * m23 + n23 * m33;
            _globalMatrices[(mtxOffset + 7)] = n21 * m14 + n22 * m24 + n23 * m34 + vec.y;
            _globalMatrices[(mtxOffset + 8)] = n31 * m11 + n32 * m21 + n33 * m31;
            _globalMatrices[(mtxOffset + 9)] = n31 * m12 + n32 * m22 + n33 * m32;
            _globalMatrices[(mtxOffset + 10)] = n31 * m13 + n32 * m23 + n33 * m33;
            _globalMatrices[(mtxOffset + 11)] = n31 * m14 + n32 * m24 + n33 * m34 + vec.z;
            mtxOffset = Std.int(mtxOffset + 12);
            ++i;
        }
    }

    /**
	 * If the animation can't be performed on GPU, transform vertices manually
	 * @param subGeom The subgeometry containing the weights and joint index data per vertex.
	 * @param pass The material pass for which we need to transform the vertices
	 */
    private function morphGeometry(state:SubGeomAnimationState, subGeom:SkinnedSubGeometry):Void {
        var vertexData:Vector<Float> = subGeom.vertexData;
        var targetData:Vector<Float> = state.animatedVertexData;
        var jointIndices:Vector<UInt> = subGeom.jointIndexData;
        var jointWeights:Vector<Float> = subGeom.jointWeightsData;
        var index:Int = 0;
        var j:Int = 0;
        var k:Int = 0;
        var vx:Float;
        var vy:Float;
        var vz:Float;
        var nx:Float;
        var ny:Float;
        var nz:Float;
        var tx:Float;
        var ty:Float;
        var tz:Float;
        var len:Int = vertexData.length;
        var weight:Float;
        var vertX:Float;
        var vertY:Float;
        var vertZ:Float;
        var normX:Float;
        var normY:Float;
        var normZ:Float;
        var tangX:Float;
        var tangY:Float;
        var tangZ:Float;
        var m11:Float;
        var m12:Float;
        var m13:Float;
        var m14:Float;
        var m21:Float;
        var m22:Float;
        var m23:Float;
        var m24:Float;
        var m31:Float;
        var m32:Float;
        var m33:Float;
        var m34:Float;
        while (index < len) {
            vertX = vertexData[index];
            vertY = vertexData[index + 1];
            vertZ = vertexData[index + 2];
            normX = vertexData[index + 3];
            normY = vertexData[index + 4];
            normZ = vertexData[index + 5];
            tangX = vertexData[index + 6];
            tangY = vertexData[index + 7];
            tangZ = vertexData[index + 8];
            vx = 0;
            vy = 0;
            vz = 0;
            nx = 0;
            ny = 0;
            nz = 0;
            tx = 0;
            ty = 0;
            tz = 0;
            k = 0;
            while (k < _jointsPerVertex) {
                weight = jointWeights[j];
                if (weight > 0) {
                    // implicit /3*12 (/3 because indices are multiplied by 3 for gpu matrix access, *12 because it's the matrix size)
                    var mtxOffset:Int = jointIndices[j++] << 2;
                    m11 = _globalMatrices[mtxOffset++];
                    m12 = _globalMatrices[mtxOffset++];
                    m13 = _globalMatrices[mtxOffset++];
                    m14 = _globalMatrices[mtxOffset++];
                    m21 = _globalMatrices[mtxOffset++];
                    m22 = _globalMatrices[mtxOffset++];
                    m23 = _globalMatrices[mtxOffset++];
                    m24 = _globalMatrices[mtxOffset++];
                    m31 = _globalMatrices[mtxOffset++];
                    m32 = _globalMatrices[mtxOffset++];
                    m33 = _globalMatrices[mtxOffset++];
                    m34 = _globalMatrices[mtxOffset];
                    vx += weight * (m11 * vertX + m12 * vertY + m13 * vertZ + m14);
                    vy += weight * (m21 * vertX + m22 * vertY + m23 * vertZ + m24);
                    vz += weight * (m31 * vertX + m32 * vertY + m33 * vertZ + m34);
                    nx += weight * (m11 * normX + m12 * normY + m13 * normZ);
                    ny += weight * (m21 * normX + m22 * normY + m23 * normZ);
                    nz += weight * (m31 * normX + m32 * normY + m33 * normZ);
                    tx += weight * (m11 * tangX + m12 * tangY + m13 * tangZ);
                    ty += weight * (m21 * tangX + m22 * tangY + m23 * tangZ);
                    tz += weight * (m31 * tangX + m32 * tangY + m33 * tangZ);
                    ++k;
                }

                else {
                    j += _jointsPerVertex - k;
                    k = _jointsPerVertex;
                }

            }

            targetData[index] = vx;
            targetData[index + 1] = vy;
            targetData[index + 2] = vz;
            targetData[index + 3] = nx;
            targetData[index + 4] = ny;
            targetData[index + 5] = nz;
            targetData[index + 6] = tx;
            targetData[index + 7] = ty;
            targetData[index + 8] = tz;
            index = index + 13;
        }

    }

    /**
	 * Converts a local hierarchical skeleton pose to a global pose
	 * @param targetPose The SkeletonPose object that will contain the global pose.
	 * @param skeleton The skeleton containing the joints, and as such, the hierarchical data to transform to global poses.
	 */
    private function localToGlobalPose(sourcePose:SkeletonPose, targetPose:SkeletonPose, skeleton:Skeleton):Void {
        var globalPoses:Vector<JointPose> = targetPose.jointPoses;
        var globalJointPose:JointPose;
        var joints:Vector<SkeletonJoint> = skeleton.joints;
        var len:Int = sourcePose.numJointPoses;
        var jointPoses:Vector<JointPose> = sourcePose.jointPoses;
        var parentIndex:Int;
        var joint:SkeletonJoint;
        var parentPose:JointPose;
        var pose:JointPose;
        var or:Quaternion;
        var tr:Vector3D;
        var t:Vector3D;
        var q:Quaternion;
        var x1:Float;
        var y1:Float;
        var z1:Float;
        var w1:Float;
        var x2:Float;
        var y2:Float;
        var z2:Float;
        var w2:Float;
        var x3:Float;
        var y3:Float;
        var z3:Float;
        
        // :s
        if (globalPoses.length != len) globalPoses.length = len;
        var i:Int = 0;
        while (i < len) {
            if (globalPoses[i] == null)
                globalPoses[i] = new JointPose();
            
            globalJointPose = globalPoses[i] ;
            joint = joints[i];
            parentIndex = joint.parentIndex;
            pose = jointPoses[i];
            q = globalJointPose.orientation;
            t = globalJointPose.translation;
            if (parentIndex < 0) {
                tr = pose.translation;
                or = pose.orientation;
                q.x = or.x;
                q.y = or.y;
                q.z = or.z;
                q.w = or.w;
                t.x = tr.x;
                t.y = tr.y;
                t.z = tr.z;
            }

            else {
                // append parent pose
                parentPose = globalPoses[parentIndex];

                // rotate point
                or = parentPose.orientation;
                tr = pose.translation;
                x2 = or.x;
                y2 = or.y;
                z2 = or.z;
                w2 = or.w;
                x3 = tr.x;
                y3 = tr.y;
                z3 = tr.z;
                w1 = -x2 * x3 - y2 * y3 - z2 * z3;
                x1 = w2 * x3 + y2 * z3 - z2 * y3;
                y1 = w2 * y3 - x2 * z3 + z2 * x3;
                z1 = w2 * z3 + x2 * y3 - y2 * x3;
                // append parent translation
                tr = parentPose.translation;
                t.x = -w1 * x2 + x1 * w2 - y1 * z2 + z1 * y2 + tr.x;
                t.y = -w1 * y2 + x1 * z2 + y1 * w2 - z1 * x2 + tr.y;
                t.z = -w1 * z2 - x1 * y2 + y1 * x2 + z1 * w2 + tr.z;
                // append parent orientation
                x1 = or.x;
                y1 = or.y;
                z1 = or.z;
                w1 = or.w;
                or = pose.orientation;
                x2 = or.x;
                y2 = or.y;
                z2 = or.z;
                w2 = or.w;
                q.w = w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2;
                q.x = w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2;
                q.y = w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2;
                q.z = w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2;
            }

            ++i;
        }
    }

    private function onTransitionComplete(event:AnimationStateEvent):Void {
        if (event.type == AnimationStateEvent.TRANSITION_COMPLETE) {
            event.animationNode.removeEventListener(AnimationStateEvent.TRANSITION_COMPLETE, onTransitionComplete);
            
            //if this is the current active state transition, revert control to the active node
            if (_activeState == event.animationState) {
                _activeNode = _animationSet.getAnimation(_activeAnimationName);
                _activeState = getAnimationState(_activeNode);
                _activeSkeletonState = cast(_activeState, ISkeletonAnimationState) ;
            }
        }
    }
}

class SubGeomAnimationState {

    public var animatedVertexData:Vector<Float>;
    public var dirty:Bool;

    public function new(subGeom:CompactSubGeometry) {
        dirty = true;
        animatedVertexData = subGeom.vertexData.slice(0, subGeom.vertexData.length);
    }
}

