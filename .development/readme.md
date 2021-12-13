# Development environment

Use VSCode to open the root folder of this repository.
Press `Ctrl+<backtick>` to open the terminal window. Preferably powershell. 
I have prepared a container image with all the tools installed that you might need, so that you can develop in this project without polluting your own system.
Some of the tools included are: 
- aws cli
- terraform
- kubectl
- git 
- openssl
- anything else I found useful during development for this project

#### Build the container image (just once)

1. `cd /.development`
2. `docker build -t terraformer .`
3. `cd ..` # go back to the root directory

#### Interactively run the container as your build environment

Working from the VSCode terminal:

Start the container, mounting this repository's root folder in the /work folder in the container.
`docker run -it --rm -w /work -v ${PWD}:/work --name signalsformer --entrypoint /bin/sh terraformer`

Login to the terraform backend
`terraform login` # use the terraform token provided privately
`terraform init`

At this point, `terraform apply` should be working, and executing on the remote backend.
You may need to run `kubectl` commands to check your work. To do so, you will need to login to AWS using the tokens provided privately: 
Also set default region to `us-east-2` and default output to `json`
`aws configure`

With that done, you can update your kubeconfig file:
`aws eks update-kubeconfig --name signals`

And now kubectl will be working for you.
