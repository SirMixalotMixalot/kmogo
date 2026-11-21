import Foundation
import Supabase

enum Backend {
    // Publishable client credentials. Database policies enforce each user's access.
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://bqdwblrelgofqkabmzhr.supabase.co")!,
        supabaseKey: "sb_publishable_GcCrC2hph_Bi23sWIMNt4g_rL1C3IoF",
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true)
        )
    )
}
