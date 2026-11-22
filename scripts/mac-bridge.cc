// Start Node in the app's own process so macOS can attribute LAN access to Otoha.
namespace node {
int Start(int argc, char* argv[]);
}
int main(int argc, char* argv[]) { return node::Start(argc, argv); }
