OPT = -O3 -fomit-frame-pointer
CPPFLAGS = -I../enet/include `sdl-config --cflags`
LIBS = -L../enet -lenet `sdl-config --libs` -lSDL_image -lSDL_mixer -lz -lGL -lGLU -lX11

CLIENT_SRCS = Cube.mm			\
	      MD2.mm			\
	      client.mm			\
	      clientextras.mm		\
	      clientgame.mm		\
	      clients2c.mm		\
	      command.mm 		\
	      console.mm		\
	      editing.mm		\
	      entities.mm		\
	      menus.mm			\
	      monster.mm		\
	      physics.mm		\
	      rendercubes.mm		\
	      renderextras.mm		\
	      rendergl.mm		\
	      renderparticles.mm	\
	      rendertext.mm 		\
	      rndmap.mm 		\
	      savegamedemo.mm 		\
	      server.mm 		\
	      serverbrowser.mm 		\
	      serverms.mm 		\
	      serverutil.mm 		\
	      sound.mm 			\
	      tools.mm 			\
	      weapon.mm 		\
	      world.mm 			\
	      worldio.mm 		\
	      worldlight.mm 		\
	      worldocull.mm 		\
	      worldrender.mm

SERVER_SRCS = server.mm		\
	      serverms.mm	\
	      serverutil.mm	\
	      tools.mm

all: ../bin/client ../bin/server

enet:
	make -C ../enet all

clean:
	rm -fr ../build ../bin
	make -C ../enet clean

../bin/client: enet
	@mkdir -p ../bin
	@objfw-compile --builddir ../build/client -o $@	\
		${CLIENT_SRCS} ${OPT} ${CPPFLAGS} ${LIBS}

../bin/server: enet
	@mkdir -p ../bin
	@objfw-compile --builddir ../build/server -o $@   \
		${SERVER_SRCS} ${OPT} ${CPPFLAGS} ${LIBS} \
		-DSTANDALONE
