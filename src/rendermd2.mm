// rendermd2.cpp: loader code adapted from a nehe tutorial

#import <ObjFW/ObjFW.h>

#include "cube.h"

struct md2_header {
	int magic;
	int version;
	int skinWidth, skinHeight;
	int frameSize;
	int numSkins, numVertices, numTexcoords;
	int numTriangles, numGlCommands, numFrames;
	int offsetSkins, offsetTexcoords, offsetTriangles;
	int offsetFrames, offsetGlCommands, offsetEnd;
};

struct md2_vertex {
	uchar vertex[3], lightNormalIndex;
};

struct md2_frame {
	float	   scale[3];
	float	   translate[3];
	char	   name[16];
	md2_vertex vertices[1];
};

@interface MD2: OFObject
{
@public
	int _numGlCommands;
	int* _glCommands;
	int _numTriangles;
	int _frameSize;
	int _numFrames;
	int _numVerts;
	char* _frames;
	vec **_mverts;
	int _displaylist;
	int _displaylistverts;

	mapmodelinfo _mmi;
	char *_loadname;
	int _mdlnum;
	bool _loaded;
}

- (void)loadFile: (char*)filename;
- (void)renderWithLight: (vec&)light
		  frame: (int)frame
		  range: (int)range
		      x: (float)x
		      y: (float)y
		      z: (float)z
		    yaw: (float)yaw
		  pitch: (float)pitch
		  scale: (float)scale
		  speed: (float)speed
		   snap: (int)snap
	       basetime: (int)basetime;
- (void)scaleWithFrame: (int)frame
		 scale: (float)scale
		    sn: (int)sn;
@end

@implementation MD2
- (void)loadFile: (char*)filename
{
	OFAutoreleasePool *pool = [OFAutoreleasePool new];
	OFString *path;
	OFFile *file;
	md2_header header;

	path = [OFString stringWithUTF8String: filename];
	file = [OFFile fileWithPath: path
			       mode: @"rb"];

	[file readIntoBuffer: &header
		 exactLength: sizeof(md2_header)];
	endianswap(&header, sizeof(int), sizeof(md2_header) / sizeof(int));

	if (header.magic != 844121161 || header.version != 8)
		@throw [OFUnsupportedVersionException
		    exceptionWithClass: [self class]];

	_frames = (char*)[self allocMemoryWithSize: header.frameSize
					     count: header.numFrames];

	[file seekToOffset: header.offsetFrames
		    whence: SEEK_SET];
	[file readIntoBuffer: _frames
		 exactLength: header.frameSize * header.numFrames];

	for (int i = 0; i < header.numFrames; ++i)
		endianswap(_frames + i * header.frameSize, sizeof(float), 6);

	_glCommands = (int*)[self allocMemoryWithSize: sizeof(int)
						count: header.numGlCommands];

	[file seekToOffset: header.offsetGlCommands
		    whence: SEEK_SET];
	[file readIntoBuffer: _glCommands
		 exactLength: header.numGlCommands * sizeof(int)];

	endianswap(_glCommands, sizeof(int), header.numGlCommands);

	_numFrames     = header.numFrames;
	_numGlCommands = header.numGlCommands;
	_frameSize     = header.frameSize;
	_numTriangles  = header.numTriangles;
	_numVerts      = header.numVertices;

	// TODO: allocMemoryWithSize:?
	_mverts = new vec*[_numFrames];
	loopj(_numFrames) _mverts[j] = NULL;

	[pool release];
}

float
snap(int sn, float f)
{
	return (sn ? (float)(((int)(f + sn * 0.5f)) & (~(sn - 1))) : f);
}

- (void)scaleWithFrame: (int)frame
		 scale: (float)scale
		    sn: (int)sn
{
	_mverts[frame] = new vec[_numVerts];
	md2_frame *cf = (md2_frame *) ((char*)_frames + _frameSize * frame);
	float sc = 16.0f / scale;

	loop(vi, _numVerts) {
		uchar *cv = (uchar *)&cf->vertices[vi].vertex;
		vec *v = &(_mverts[frame])[vi];
		v->x =  (snap(sn, cv[0] * cf->scale[0])+cf->translate[0]) / sc;
		v->y = -(snap(sn, cv[1] * cf->scale[1])+cf->translate[1]) / sc;
		v->z =  (snap(sn, cv[2] * cf->scale[2])+cf->translate[2]) / sc;
	}
}

- (void)renderWithLight: (vec&)light
		  frame: (int)frame
		  range: (int)range
		      x: (float)x
		      y: (float)y
		      z: (float)z
		    yaw: (float)yaw
		  pitch: (float)pitch
		  scale: (float)scale
		  speed: (float)speed
		   snap: (int)snap
	       basetime: (int)basetime
{
	loopi(range)
		if(!_mverts[frame+i])
			[self scaleWithFrame: frame + i
				       scale: scale
					  sn: snap];

	glPushMatrix();
	glTranslatef(x, y, z);
	glRotatef(yaw+180, 0, -1, 0);
	glRotatef(pitch, 0, 0, 1);

	glColor3fv((float *)&light);

	if (_displaylist && frame == 0 && range == 1) {
		glCallList(_displaylist);
		xtraverts += _displaylistverts;
	} else {
		if (frame == 0 && range == 1) {
			static int displaylistn = 10;
			glNewList(_displaylist = displaylistn++, GL_COMPILE);
			_displaylistverts = xtraverts;
		}

		int time = lastmillis - basetime;
		int fr1 = (int)(time / speed);
		float frac1 = (time - fr1 * speed) / speed;
		float frac2 = 1 - frac1;
		fr1 = fr1 % range + frame;
		int fr2 = fr1 + 1;
		if (fr2 >= frame + range) fr2 = frame;
		vec *verts1 = _mverts[fr1];
		vec *verts2 = _mverts[fr2];

		for (int *command = _glCommands; (*command) != 0;) {
			int numVertex = *command++;
			if (numVertex > 0)
				glBegin(GL_TRIANGLE_STRIP);
			else {
				glBegin(GL_TRIANGLE_FAN);
				numVertex = -numVertex;
			}

			loopi(numVertex) {
				float tu = *((float*)command++);
				float tv = *((float*)command++);
				glTexCoord2f(tu, tv);
				int vn = *command++;
				vec &v1 = verts1[vn];
				vec &v2 = verts2[vn];
				#define ip(c) v1.c*frac2+v2.c*frac1
				glVertex3f(ip(x), ip(z), ip(y));
			}

			xtraverts += numVertex;

			glEnd();
		}

		if (_displaylist) {
			glEndList();
			_displaylistverts = xtraverts - _displaylistverts;
		}
	}

	glPopMatrix();
}
@end

OFMutableDictionary *mdllookup = nil;
OFMutableArray *mapmodels = nil;
const int FIRSTMDL = 20;

void delayedload(MD2 *m)
{
	if (!m->_loaded) {
		sprintf_sd(name1)("packages/models/%s/tris.md2", m->_loadname);
		@try {
			[m loadFile: path(name1)];
		} @catch (id e) {
			fatal("loadmodel: ", name1);
		}
		sprintf_sd(name2)("packages/models/%s/skin.jpg", m->_loadname);
		int xs, ys;
		installtex(FIRSTMDL + m->_mdlnum, path(name2), xs, ys);
		m->_loaded = true;
	}
}

int modelnum = 0;

MD2*
loadmodel(char *name_)
{
	OFAutoreleasePool *pool = [OFAutoreleasePool new];
	OFString *name = [OFString stringWithUTF8String: name_];

	if (mdllookup == nil)
		mdllookup = [OFMutableDictionary new];

	MD2 *m = [mdllookup objectForKey: name];
	if (m != nil) {
		[pool release];
		return m;
	}

	m = [[MD2 new] autorelease];
	m->_mdlnum = modelnum++;
	mapmodelinfo mmi = { 2, 2, 0, 0, "" };
	m->_mmi = mmi;
	m->_loadname = newstring(name_);

	[mdllookup setObject: m
		      forKey: name];

	[pool release];

	return m;
}

void
mapmodel(char *rad, char *h, char *zoff, char *snap, char *name)
{
	MD2 *m = loadmodel(name);
	mapmodelinfo mmi = { atoi(rad), atoi(h), atoi(zoff), atoi(snap),
		m->_loadname };
	m->_mmi = mmi;
	[mapmodels addObject: m];
};

void
mapmodelreset()
{
	[mapmodels removeAllObjects];
}

mapmodelinfo&
getmminfo(int i)
{
	if (i < mapmodels.count) {
		MD2 *m = [mapmodels objectAtIndex: i];
		return m->_mmi;
	}

	return *(mapmodelinfo*)0;
}

COMMAND(mapmodel, ARG_5STR);
COMMAND(mapmodelreset, ARG_NONE);

void
rendermodel(char *mdl, int frame, int range, int tex, float rad, float x,
    float y, float z, float yaw, float pitch, bool teammate, float scale,
    float speed, int snap, int basetime)
{
	MD2 *m = loadmodel(mdl);

	if (isoccluded(player1->o.x, player1->o.y, x-rad, z-rad, rad * 2))
		return;

	delayedload(m);

	int xs, ys;
	glBindTexture(GL_TEXTURE_2D,
	    tex ? lookuptexture(tex, xs, ys) : FIRSTMDL + m->_mdlnum);

	int ix = (int)x;
	int iy = (int)z;
	vec light = { 1.0f, 1.0f, 1.0f };

	if (!OUTBORD(ix, iy)) {
		sqr *s = S(ix, iy);
		float ll = 256.0f; // 0.96f;
		float of = 0.0f; // 0.1f;
		light.x = s->r / ll + of;
		light.y = s->g / ll + of;
		light.z = s->b / ll + of;
	}

	if (teammate) {
		light.x *= 0.6f;
		light.y *= 0.7f;
		light.z *= 1.2f;
	}

	[m renderWithLight: light
		     frame: frame
		     range: range
			 x: x
			 y: y
			 z: z
		       yaw: yaw
		     pitch: pitch
		     scale: scale
		     speed: speed
		      snap: snap
		  basetime: basetime];
}
