/^use Pterodactyl\\Repositories\\Eloquent\\ServerRepository;$/a\
use Pterodactyl\\Repositories\\Wings\\DaemonFileRepository; // blueprintframework:deleteonreinstall
/private ReinstallServerService \$reinstallServerService,/a\
        private DaemonFileRepository $daemonFileRepository, // blueprintframework:deleteonreinstall
/\$this->reinstallServerService->handle(\$server);/i\
        // blueprintframework:deleteonreinstall:start\
        if ($request->boolean('truncate')) {\
            $files = array_column(\
                $this->daemonFileRepository->setServer($server)->getDirectory('/'),\
                'name'\
            );\
            if (count($files) > 0) {\
                $this->daemonFileRepository->setServer($server)->deleteFiles('/', $files);\
            }\
        }\
        // blueprintframework:deleteonreinstall:end
